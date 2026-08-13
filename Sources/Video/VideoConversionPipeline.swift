@preconcurrency import AVFoundation
import Foundation

#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

extension VideoTool {

    internal static func convertImpl(
        source: URL,
        destination: URL,
        fileType: VideoFileType = .mov,
        videoSettings: CompressionVideoSettings = CompressionVideoSettings(),
        optimizeForNetworkUse: Bool = true,
        skipAudio: Bool = false,
        audioSettings: CompressionAudioSettings? = nil,
        skipSourceMetadata: Bool = false,
        customMetadata: [AVMetadataItem] = [],
        copyExtendedFileMetadata: Bool = true,
        cacheDirectory: URL? = nil,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false,
        progressQueue: DispatchQueue = .main,
        callback: @escaping (CompressionState) -> Void
    ) async -> CompressionTask {
        let task = CompressionTask(destination: destination)
        let session = VideoConversionSession(
            task: task,
            source: source,
            destination: destination,
            fileType: fileType,
            videoSettings: videoSettings,
            optimizeForNetworkUse: optimizeForNetworkUse,
            skipAudio: skipAudio,
            audioSettings: audioSettings,
            skipSourceMetadata: skipSourceMetadata,
            customMetadata: customMetadata,
            copyExtendedFileMetadata: copyExtendedFileMetadata,
            cacheDirectory: cacheDirectory,
            overwrite: overwrite,
            deleteSourceFile: deleteSourceFile,
            progressQueue: progressQueue,
            callback: callback
        )

        await session.prepareAndStart()
        return task
    }
}

/// Owns every AVFoundation object involved in one conversion. Its state queue is
/// the only place where readers, writers, inputs, outputs, and sample pumps are
/// accessed after preparation completes.
private final class VideoConversionSession: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "MediaToolSwift.video.conversion.session")

    private let task: CompressionTask
    private let source: URL
    private let destination: URL
    private let fileType: VideoFileType
    private let videoSettings: CompressionVideoSettings
    private let optimizeForNetworkUse: Bool
    private let skipAudio: Bool
    private let audioSettings: CompressionAudioSettings?
    private let skipSourceMetadata: Bool
    private let customMetadata: [AVMetadataItem]
    private let copyExtendedFileMetadata: Bool
    private let cacheDirectory: URL?
    private let overwrite: Bool
    private let deleteSourceFile: Bool
    private let progressQueue: DispatchQueue
    private let callback: (CompressionState) -> Void

    private var configuration: PreparedVideoConversion?
    private var pumps: [VideoTrackPump] = []
    private var progress: CompressionVideoProgress?
    private var cancellationHandlerID: UUID?
    private var isFinishing = false
    private var isTerminal = false
    private var retainedSession: VideoConversionSession?
    private var destinationExistedAtStart = false

    init(
        task: CompressionTask,
        source: URL,
        destination: URL,
        fileType: VideoFileType,
        videoSettings: CompressionVideoSettings,
        optimizeForNetworkUse: Bool,
        skipAudio: Bool,
        audioSettings: CompressionAudioSettings?,
        skipSourceMetadata: Bool,
        customMetadata: [AVMetadataItem],
        copyExtendedFileMetadata: Bool,
        cacheDirectory: URL?,
        overwrite: Bool,
        deleteSourceFile: Bool,
        progressQueue: DispatchQueue,
        callback: @escaping (CompressionState) -> Void
    ) {
        self.task = task
        self.source = source
        self.destination = destination
        self.fileType = fileType
        self.videoSettings = videoSettings
        self.optimizeForNetworkUse = optimizeForNetworkUse
        self.skipAudio = skipAudio
        self.audioSettings = audioSettings
        self.skipSourceMetadata = skipSourceMetadata
        self.customMetadata = customMetadata
        self.copyExtendedFileMetadata = copyExtendedFileMetadata
        self.cacheDirectory = cacheDirectory
        self.overwrite = overwrite
        self.deleteSourceFile = deleteSourceFile
        self.progressQueue = progressQueue
        self.callback = callback
    }

    func prepareAndStart() async {
        stateQueue.sync {
            retainedSession = self
            destinationExistedAtStart = FileManager.default.fileExists(atPath: destination.path)
            cancellationHandlerID = task.registerCancellationHandler { [weak self] in
                self?.requestCancellation()
            }
        }

        guard !task.isCancelled, !terminalStateReached() else {
            requestCancellation()
            return
        }

        do {
            let prepared = try await prepareConfiguration()

            guard !task.isCancelled, !terminalStateReached() else {
                requestCancellation()
                return
            }

            stateQueue.sync {
                installAndStartOnQueue(prepared)
            }
        } catch {
            if task.isCancelled {
                requestCancellation()
            } else {
                finishPreparation(with: error)
            }
        }
    }

    private func prepareConfiguration() async throws -> PreparedVideoConversion {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompressionError.sourceFileNotFound
        }

        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw CompressionError.cannotOverWrite
        }

        let destinationExisted = FileManager.default.fileExists(atPath: destination.path)
        guard !destinationExisted || overwrite else {
            throw CompressionError.destinationFileExists
        }

        guard destination.pathExtension.lowercased() == fileType.rawValue else {
            throw CompressionError.invalidFileType
        }

        let asset = AVAsset(url: source)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType.value)
        writer.directoryForTemporaryFiles = cacheDirectory

        let video = try await VideoTool.initializeVideo(asset: asset, videoSettings: videoSettings)
        var audio: AudioVariables
        if skipAudio {
            audio = AudioVariables()
            audio.skipAudio = true

            if !video.hasChanges {
                audio.audioTrack = await asset.getFirstTrack(withMediaType: .audio)
                audio.hasChanges = audio.audioTrack != nil
            }
        } else {
            audio = try await VideoTool.initializeAudio(asset: asset, audioSettings: audioSettings)
        }

        guard video.hasChanges || audio.hasChanges else {
            throw CompressionError.redundantCompression
        }

        let metadata = await VideoTool.initializeMetadata(
            asset: asset,
            skipSourceMetadata: skipSourceMetadata,
            customMetadata: customMetadata
        )

        // `video` is mutable in the setup code above and then has exclusive
        // ownership transferred to the session queue in PreparedVideoConversion.
        return PreparedVideoConversion(
            asset: asset,
            reader: reader,
            writer: writer,
            video: video,
            audio: audio,
            metadata: metadata,
            destinationExisted: destinationExisted
        )
    }

    private func installAndStartOnQueue(_ prepared: PreparedVideoConversion) {
        guard !isTerminal else { return }

        configuration = prepared
        do {
            try configureTracksOnQueue(prepared)
        } catch {
            failOnQueue(error)
            return
        }

        prepared.writer.shouldOptimizeForNetworkUse = optimizeForNetworkUse
        if let frameRate = prepared.video.frameRate {
            prepared.writer.movieTimeScale = CMTimeScale(frameRate)
        }
        prepared.writer.metadata = prepared.metadata.metadata

        if prepared.destinationExisted {
            do {
                try FileManager.default.removeItem(at: destination)
                prepared.replacedExistingDestination = true
            } catch {
                failOnQueue(error)
                return
            }
        }

        if let timeRange = prepared.video.range {
            prepared.reader.timeRange = timeRange
        }

        guard prepared.reader.startReading() else {
            failOnQueue(prepared.reader.error ?? CompressionError.failedToReadVideo)
            return
        }

        guard prepared.writer.startWriting() else {
            failOnQueue(prepared.writer.error ?? CompressionError.failedToWriteVideo)
            return
        }
        prepared.didStartWriting = true

        prepared.writer.startSession(atSourceTime: prepared.video.range?.start ?? .zero)

        progress = CompressionVideoProgress(
            task: task,
            timeRange: prepared.video.range ?? CMTimeRange(start: .zero, duration: prepared.video.sourceDuration),
            estimatedFileLengthInKB: prepared.video.estimatedFileLength ?? 0,
            frameRate: prepared.video.nominalFrameRate,
            destination: destination,
            queue: progressQueue,
            config: optimizeForNetworkUse || !prepared.video.isEstimatedFileSizeAccurate ? .disabled : .matching
        )

        callback(.started)
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        pumps = [
            VideoTrackPump(
                kind: .video,
                input: prepared.video.videoInput,
                output: prepared.video.videoOutput,
                sampleHandler: prepared.video.sampleHandler
            )
        ]

        if !prepared.audio.skipAudio,
           let input = prepared.audio.audioInput,
           let output = prepared.audio.audioOutput {
            pumps.append(VideoTrackPump(kind: .audio, input: input, output: output))
        }

        if prepared.metadata.hasMetadata,
           let input = prepared.metadata.metadataInput,
           let output = prepared.metadata.metadataOutput {
            pumps.append(VideoTrackPump(kind: .metadata, input: input, output: output))
        }

        startPumpsOnQueue()
    }

    private func configureTracksOnQueue(_ prepared: PreparedVideoConversion) throws {
        guard prepared.reader.canAdd(prepared.video.videoOutput) else {
            throw CompressionError.failedToReadVideo
        }
        guard prepared.writer.canAdd(prepared.video.videoInput) else {
            throw CompressionError.failedToWriteVideo
        }

        #if canImport(ObjCExceptionCatcher)
        try ObjCExceptionCatcher.catchException {
            prepared.reader.add(prepared.video.videoOutput)
            prepared.writer.add(prepared.video.videoInput)
            return
        }
        #else
        prepared.reader.add(prepared.video.videoOutput)
        prepared.writer.add(prepared.video.videoInput)
        #endif

        if !prepared.audio.skipAudio,
           let audioOutput = prepared.audio.audioOutput,
           let audioInput = prepared.audio.audioInput {
            guard prepared.reader.canAdd(audioOutput) else {
                throw CompressionError.failedToReadAudio
            }
            guard prepared.writer.canAdd(audioInput) else {
                throw CompressionError.failedToWriteAudio
            }

            #if canImport(ObjCExceptionCatcher)
            try ObjCExceptionCatcher.catchException {
                prepared.reader.add(audioOutput)
                prepared.writer.add(audioInput)
                return
            }
            #else
            prepared.reader.add(audioOutput)
            prepared.writer.add(audioInput)
            #endif
        }

        if prepared.metadata.hasMetadata,
           let metadataOutput = prepared.metadata.metadataOutput {
            guard prepared.reader.canAdd(metadataOutput) else {
                throw CompressionError.failedToReadMetadata
            }
            prepared.reader.add(metadataOutput)

            if let metadataInput = prepared.metadata.metadataInput,
               prepared.writer.canAdd(metadataInput) {
                prepared.writer.add(metadataInput)
            } else {
                // Container metadata is still written through writer.metadata.
                prepared.metadata.hasMetadata = false
            }
        }
    }

    private func startPumpsOnQueue() {
        for index in pumps.indices {
            let input = pumps[index].input
            input.requestMediaDataWhenReady(on: stateQueue) { [weak self] in
                self?.pumpOnQueue(at: index)
            }
        }
    }

    private func pumpOnQueue(at index: Int) {
        guard !isTerminal, !isFinishing, let prepared = configuration, pumps.indices.contains(index) else {
            return
        }
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        let pump = pumps[index]
        guard !pump.isFinished else { return }

        var processedSamples = 0
        while pump.input.isReadyForMoreMediaData, processedSamples < 8 {
            guard !task.isCancelled else {
                cancelOnQueue()
                return
            }

            if let pending = pump.popPendingSample() {
                guard append(pending, to: pump, writer: prepared.writer) else { return }
                updateProgress(for: pending, track: pump.kind)
                processedSamples += 1
                continue
            }

            guard let sample = pump.output.copyNextSampleBuffer() else {
                if prepared.reader.status == .failed {
                    failOnQueue(prepared.reader.error ?? pump.readError)
                    return
                }

                pump.isFinished = true
                pump.input.markAsFinished()
                finishEncodingIfPossibleOnQueue()
                return
            }

            let samples = pump.sampleHandler?(sample) ?? [sample]
            if samples.isEmpty {
                if prepared.writer.status == .failed {
                    failOnQueue(prepared.writer.error ?? pump.writeError)
                    return
                }
                updateProgress(for: sample, track: pump.kind)
                processedSamples += 1
                continue
            }

            guard append(samples[0], to: pump, writer: prepared.writer) else { return }
            if samples.count > 1 {
                pump.appendPendingSamples(samples.dropFirst())
            }
            updateProgress(for: sample, track: pump.kind)
            processedSamples += 1
        }

        // Yield after a bounded batch so the other track pumps can run, then
        // explicitly schedule the next batch. AVFoundation is allowed to keep
        // the input ready without issuing another callback in between.
        if !pump.isFinished, pump.input.isReadyForMoreMediaData, !isTerminal {
            stateQueue.async { [weak self] in
                self?.pumpOnQueue(at: index)
            }
        }
    }

    private func append(
        _ sample: CMSampleBuffer,
        to pump: VideoTrackPump,
        writer: AVAssetWriter
    ) -> Bool {
        guard pump.input.append(sample) else {
            failOnQueue(writer.error ?? pump.writeError)
            return false
        }
        return true
    }

    private func updateProgress(for sample: CMSampleBuffer, track: VideoTrackKind) {
        guard track == .video else { return }
        progress?.update(sample.presentationTimeStamp)
    }

    private func finishEncodingIfPossibleOnQueue() {
        guard !isTerminal, !isFinishing, pumps.allSatisfy(\.isFinished), let prepared = configuration else {
            return
        }
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        isFinishing = true
        progress?.complete()
        prepared.reader.cancelReading()
        prepared.writer.finishWriting { [weak self] in
            self?.stateQueue.async { [weak self] in
                self?.finishWritingOnQueue()
            }
        }
    }

    private func finishWritingOnQueue() {
        guard !isTerminal, let prepared = configuration else { return }
        guard !task.isCancelled, prepared.writer.status == .completed else {
            if task.isCancelled || prepared.writer.status == .cancelled {
                cancelOnQueue()
            } else {
                failOnQueue(prepared.writer.error ?? CompressionError.failedToWriteVideo)
            }
            return
        }

        progress?.completeWriting()
        let data = FileExtendedAttributes.setExtendedMetadata(
            source: source,
            destination: destination,
            copy: copyExtendedFileMetadata,
            fileType: fileType
        )
        let extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: data)

        guard task.claimSuccessfulTerminalOutcome() else {
            cancelOnQueue()
            return
        }

        let videoInfo = VideoInfo(
            url: prepared.writer.outputURL,
            resolution: prepared.video.size.oriented(prepared.video.orientation),
            frameRate: prepared.video.frameRate ?? Int(prepared.video.nominalFrameRate.rounded()),
            totalFrames: Int(prepared.video.totalFrames),
            duration: (prepared.video.range?.duration ?? prepared.video.sourceDuration).seconds,
            videoCodec: prepared.video.codec,
            videoBitrate: prepared.video.bitrate,
            hasAlpha: prepared.video.hasAlpha,
            isHDR: prepared.video.isHDR,
            hasAudio: !prepared.audio.skipAudio,
            audioCodec: prepared.audio.codec,
            audioBitrate: prepared.audio.bitrate,
            extendedInfo: extendedInfo
        )

        if deleteSourceFile {
            try? FileManager.default.removeItem(at: source)
        }
        completeTerminalOnQueue(.completed(videoInfo))
    }

    private func requestCancellation() {
        stateQueue.async { [weak self] in
            self?.cancelOnQueue()
        }
    }

    private func cancelOnQueue() {
        guard !isTerminal else { return }
        if let prepared = configuration {
            prepared.reader.cancelReading()
            prepared.writer.cancelWriting()
            pumps.forEach { $0.input.markAsFinished() }
        }
        progress?.cancelWriting()
        removePartialOutputOnQueue()
        completeTerminalOnQueue(.cancelled)
    }

    private func failOnQueue(_ error: Error) {
        guard !isTerminal else { return }
        if let prepared = configuration {
            prepared.reader.cancelReading()
            prepared.writer.cancelWriting()
            pumps.forEach { $0.input.markAsFinished() }
        }
        progress?.cancelWriting()
        removePartialOutputOnQueue()
        completeTerminalOnQueue(.failed(error))
    }

    private func finishPreparation(with error: Error) {
        let failure = VideoConversionFailure(error)
        stateQueue.async { [weak self, failure] in
            self?.failOnQueue(failure.error)
        }
    }

    private func removePartialOutputOnQueue() {
        guard let prepared = configuration else {
            // A writer may have created an empty file while asynchronous setup
            // was still in progress. It is safe to remove only a path that did
            // not exist when this conversion began.
            guard !destinationExistedAtStart else { return }
            try? FileManager.default.removeItem(at: destination)
            return
        }

        guard !prepared.destinationExisted || prepared.replacedExistingDestination || prepared.didStartWriting else {
            return
        }
        try? FileManager.default.removeItem(at: destination)
    }

    private func completeTerminalOnQueue(_ state: CompressionState) {
        guard !isTerminal else { return }
        isTerminal = true
        task.markTerminalOutcome()
        task.removeCancellationHandler(cancellationHandlerID)
        cancellationHandlerID = nil
        callback(state)
        pumps.removeAll()
        configuration = nil
        progress = nil
        retainedSession = nil
    }

    private func terminalStateReached() -> Bool {
        stateQueue.sync { isTerminal }
    }
}

/// A one-way ownership transfer from asynchronous preparation to the conversion
/// session's serial queue. AVFoundation values are never used by both at once.
private final class PreparedVideoConversion: @unchecked Sendable {
    let asset: AVAsset
    let reader: AVAssetReader
    let writer: AVAssetWriter
    var video: VideoVariables
    var audio: AudioVariables
    var metadata: MetadataVariables
    let destinationExisted: Bool
    var replacedExistingDestination = false
    var didStartWriting = false

    init(
        asset: AVAsset,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        video: VideoVariables,
        audio: AudioVariables,
        metadata: MetadataVariables,
        destinationExisted: Bool
    ) {
        self.asset = asset
        self.reader = reader
        self.writer = writer
        self.video = video
        self.audio = audio
        self.metadata = metadata
        self.destinationExisted = destinationExisted
    }
}

private final class VideoConversionFailure: @unchecked Sendable {
    let error: Error

    init(_ error: Error) {
        self.error = error
    }
}

private enum VideoTrackKind {
    case video
    case audio
    case metadata
}

private final class VideoTrackPump {
    let kind: VideoTrackKind
    let input: AVAssetWriterInput
    let output: AVAssetReaderOutput
    let sampleHandler: ((CMSampleBuffer) -> [CMSampleBuffer])?
    var isFinished = false
    private var pendingSamples: [CMSampleBuffer] = []

    init(
        kind: VideoTrackKind,
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        sampleHandler: ((CMSampleBuffer) -> [CMSampleBuffer])? = nil
    ) {
        self.kind = kind
        self.input = input
        self.output = output
        self.sampleHandler = sampleHandler
    }

    var readError: CompressionError {
        switch kind {
        case .video:
            return .failedToReadVideo
        case .audio:
            return .failedToReadAudio
        case .metadata:
            return .failedToReadMetadata
        }
    }

    var writeError: CompressionError {
        switch kind {
        case .video:
            return .failedToWriteVideo
        case .audio:
            return .failedToWriteAudio
        case .metadata:
            return .failedToWriteVideo
        }
    }

    func popPendingSample() -> CMSampleBuffer? {
        guard !pendingSamples.isEmpty else { return nil }
        return pendingSamples.removeFirst()
    }

    func appendPendingSamples(_ samples: ArraySlice<CMSampleBuffer>) {
        pendingSamples.append(contentsOf: samples)
    }
}
