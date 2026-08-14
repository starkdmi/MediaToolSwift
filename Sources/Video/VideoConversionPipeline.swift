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

        await withTaskCancellationHandler {
            await session.prepareAndStart()
        } onCancel: {
            task.cancel()
        }
        return task
    }
}

/// Owns every AVFoundation object involved in one conversion. Its state queue is
/// the only place where readers, writers, inputs, outputs, and sample pumps are
/// accessed after preparation completes.
private final class VideoConversionSession: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "MediaToolSwift.video.conversion.session")
    private let processingQueue: DispatchQueue

    /// Serializes composition reads against reader cancellation.
    ///
    /// `AVAssetReader.cancelReading()` must not run concurrently with
    /// `copyNextSampleBuffer()`, so both are confined to this queue. It is kept
    /// separate from `processingQueue` to keep cancellation latency bounded by a
    /// single read rather than by a caller-supplied frame processor.
    private let readQueue: DispatchQueue

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
    private let callbackDelivery: LegacyCallbackDelivery<CompressionState>

    private var configuration: PreparedVideoConversion?
    private var pumps: [VideoTrackPump] = []
    private var progress: CompressionVideoProgress?
    private var cancellationHandlerID: UUID?
    private var isFinishing = false
    private var isTerminal = false
    private var retainedSession: VideoConversionSession?

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
        let processingQueue = DispatchQueue(label: "MediaToolSwift.video.frame-processing")
        self.processingQueue = processingQueue
        readQueue = DispatchQueue(label: "MediaToolSwift.video.sample-reading")
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
        // Deliberately shares `processingQueue` with the public frame processor.
        // A terminal callback must never overlap an in-flight processor, and the
        // serial queue is what enforces that. Only `.started` and one terminal
        // state travel this path, both at points where no frame work is pending,
        // so the sharing costs no frame-processing throughput.
        callbackDelivery = LegacyCallbackDelivery(
            label: "MediaToolSwift.video.callback",
            queue: processingQueue,
            callback: callback
        )
    }

    func prepareAndStart() async {
        // Never block a cooperative pool thread on the session queue. Handler
        // registration is ordered ahead of every other `stateQueue` block, and
        // `registerCancellationHandler` invokes the handler itself when the task
        // is already cancelled, so an asynchronous handoff loses no cancellation.
        stateQueue.async { [self] in
            retainedSession = self
            cancellationHandlerID = task.registerCancellationHandler { [weak self] in
                self?.requestCancellation()
            }
        }

        // A terminal state before the configuration is installed can only come
        // from cancellation, which `claimCancellationTerminalOutcome` reflects in
        // `task.isCancelled`. Reading it avoids a synchronous queue hop.
        guard !task.isCancelled else {
            requestCancellation()
            return
        }

        do {
            let prepared = try await prepareConfiguration()

            guard !task.isCancelled else {
                requestCancellation()
                return
            }

            stateQueue.async { [self] in
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
        guard !task.isCancelled, !Task.isCancelled else {
            throw CancellationError()
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompressionError.sourceFileNotFound
        }
        let sourceFileIdentity = deleteSourceFile
            ? SourceFileIdentity(at: source)
            : nil

        guard !fileURLsReferToSameItem(source, destination) else {
            throw CompressionError.cannotOverWrite
        }

        let outputTransaction = try FileOutputTransaction(
            destination: destination,
            overwrite: overwrite
        )

        guard destination.pathExtension.lowercased() == fileType.rawValue else {
            throw CompressionError.invalidFileType
        }

        let asset = AVAsset(url: source)
        let reader = try AVAssetReader(asset: asset)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(
                outputURL: outputTransaction.outputURL,
                fileType: fileType.value
            )
            outputTransaction.captureOutputIdentityIfPresent()
        } catch {
            outputTransaction.discard()
            throw error
        }
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
            outputTransaction: outputTransaction,
            sourceFileIdentity: sourceFileIdentity
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

        if let timeRange = prepared.video.range {
            prepared.reader.timeRange = timeRange
        }

        guard prepared.reader.startReading() else {
            failOnQueue(prepared.reader.error ?? CompressionError.failedToReadVideo)
            return
        }

        let didStartWriting = prepared.writer.startWriting()
        prepared.outputTransaction.captureOutputIdentityIfPresent()
        guard didStartWriting else {
            failOnQueue(prepared.writer.error ?? CompressionError.failedToWriteVideo)
            return
        }
        prepared.writer.startSession(atSourceTime: prepared.video.range?.start ?? .zero)

        progress = CompressionVideoProgress(
            task: task,
            timeRange: prepared.video.range ?? CMTimeRange(start: .zero, duration: prepared.video.sourceDuration),
            estimatedFileLengthInKB: prepared.video.estimatedFileLength ?? 0,
            frameRate: prepared.video.nominalFrameRate,
            destination: destination,
            observedOutput: prepared.outputTransaction.outputURL,
            queue: progressQueue,
            config: optimizeForNetworkUse || !prepared.video.isEstimatedFileSizeAccurate ? .disabled : .matching
        )

        callbackDelivery.enqueue(.started) { [weak self] in
            self?.stateQueue.async { [weak self] in
                self?.startPumpsAfterStartedOnQueue()
            }
        }
    }

    private func startPumpsAfterStartedOnQueue() {
        guard !isTerminal, !isFinishing, let prepared = configuration else { return }
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        pumps = [
            VideoTrackPump(
                kind: .video,
                input: prepared.video.videoInput,
                output: prepared.video.videoOutput,
                sampleHandler: prepared.video.sampleHandler,
                readsAsynchronously: isVideoCompositionOutput(prepared.video.videoOutput)
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
        guard !pump.isFinished, !pump.isProcessing else { return }

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

            if pump.readsAsynchronously {
                pump.isProcessing = true
                let work = VideoSampleReadWork(output: pump.output)
                readQueue.async { [weak self, work] in
                    let result = work.run()
                    self?.stateQueue.async { [weak self, result] in
                        self?.finishReadOnQueue(result, at: index)
                    }
                }
                return
            }

            guard let sample = pump.output.copyNextSampleBuffer() else {
                if prepared.reader.status == .failed {
                    failOnQueue(prepared.reader.error ?? pump.readError)
                    return
                }

                guard markInputFinishedOnQueue(pump, writer: prepared.writer) else { return }
                pump.isFinished = true
                finishEncodingIfPossibleOnQueue()
                return
            }

            if let sampleHandler = pump.sampleHandler {
                pump.isProcessing = true
                let work = VideoSampleProcessingWork(
                    sample: sample,
                    pixelBufferPool: prepared.video.videoInputAdaptor?.pixelBufferPool,
                    handler: sampleHandler
                )
                processingQueue.async { [weak self, work] in
                    let result = work.run()
                    self?.stateQueue.async { [weak self, result] in
                        self?.finishProcessingOnQueue(result, at: index)
                    }
                }
                return
            }

            // Without a sample handler a read yields exactly one sample, so it
            // is appended directly and never queues follow-up samples.
            guard append(sample, to: pump, writer: prepared.writer) else { return }
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

    private func finishReadOnQueue(_ result: VideoSampleReadResult, at index: Int) {
        guard !isTerminal,
              !isFinishing,
              let prepared = configuration,
              pumps.indices.contains(index) else {
            return
        }
        let pump = pumps[index]
        pump.isProcessing = false
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        guard let sample = result.sample else {
            if prepared.reader.status == .failed {
                failOnQueue(prepared.reader.error ?? pump.readError)
            } else {
                guard markInputFinishedOnQueue(pump, writer: prepared.writer) else { return }
                pump.isFinished = true
                finishEncodingIfPossibleOnQueue()
            }
            return
        }

        if let sampleHandler = pump.sampleHandler {
            pump.isProcessing = true
            let work = VideoSampleProcessingWork(
                sample: sample,
                pixelBufferPool: prepared.video.videoInputAdaptor?.pixelBufferPool,
                handler: sampleHandler
            )
            processingQueue.async { [weak self, work] in
                let result = work.run()
                self?.stateQueue.async { [weak self, result] in
                    self?.finishProcessingOnQueue(result, at: index)
                }
            }
        } else {
            guard append(sample, to: pump, writer: prepared.writer) else { return }
            updateProgress(for: sample, track: pump.kind)
            stateQueue.async { [weak self] in
                self?.pumpOnQueue(at: index)
            }
        }
    }

    private func isVideoCompositionOutput(_ output: AVAssetReaderOutput) -> Bool {
        #if os(visionOS)
        return false
        #else
        return output is AVAssetReaderVideoCompositionOutput
        #endif
    }

    /// Cancels the reader without overlapping an in-flight read.
    ///
    /// `AVAssetReader` forbids `cancelReading()` concurrent with
    /// `copyNextSampleBuffer()`. Synchronous reads already share `stateQueue`
    /// with this call, but composition reads run on `readQueue`, so cancellation
    /// is handed to that queue to run after any read in flight. Every remaining
    /// caller of `copyNextSampleBuffer()` on `stateQueue` is gated on
    /// `isTerminal`, which both terminal paths set before returning.
    private func cancelReadingOnQueue(_ prepared: PreparedVideoConversion) {
        guard isVideoCompositionOutput(prepared.video.videoOutput) else {
            if prepared.reader.status == .reading {
                prepared.reader.cancelReading()
            }
            return
        }

        readQueue.async { [prepared] in
            if prepared.reader.status == .reading {
                prepared.reader.cancelReading()
            }
        }
    }

    private func markInputFinishedOnQueue(
        _ pump: VideoTrackPump,
        writer: AVAssetWriter
    ) -> Bool {
        guard writer.status == .writing else {
            failOnQueue(writer.error ?? pump.writeError)
            return false
        }

        do {
            #if canImport(ObjCExceptionCatcher)
            try ObjCExceptionCatcher.catchException {
                pump.input.markAsFinished()
            }
            #else
            pump.input.markAsFinished()
            #endif
            return true
        } catch {
            failOnQueue(error)
            return false
        }
    }

    private func finishProcessingOnQueue(
        _ result: VideoSampleProcessingResult,
        at index: Int
    ) {
        guard !isTerminal,
              !isFinishing,
              let prepared = configuration,
              pumps.indices.contains(index) else {
            return
        }
        let pump = pumps[index]
        pump.isProcessing = false
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        switch result.output {
        case .dropped:
            if prepared.writer.status == .failed {
                failOnQueue(prepared.writer.error ?? pump.writeError)
                return
            }
        case .sampleBuffers(let samples):
            guard let first = samples.first else { break }
            guard append(first, to: pump, writer: prepared.writer) else { return }
            if samples.count > 1 {
                pump.appendPendingSamples(samples.dropFirst())
            }
        case .pixelBuffer(let pixelBuffer, let presentationTime):
            guard let adaptor = prepared.video.videoInputAdaptor,
                  adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                failOnQueue(prepared.writer.error ?? pump.writeError)
                return
            }
        }
        updateProgress(for: result.sourceSample, track: pump.kind)

        stateQueue.async { [weak self] in
            self?.pumpOnQueue(at: index)
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
        // Safe to cancel directly, unlike the terminal paths: every pump has
        // already finished, so no read can be in flight on `readQueue`.
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
            destination: prepared.outputTransaction.outputURL,
            copy: copyExtendedFileMetadata,
            fileType: fileType
        )
        let extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: data)

        guard task.claimSuccessfulTerminalOutcome() else {
            cancelOnQueue()
            return
        }

        do {
            try prepared.outputTransaction.commit()
        } catch {
            failOnQueue(error, taskOutcomeAlreadyClaimed: true)
            return
        }

        let videoInfo = VideoInfo(
            url: destination,
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

        prepared.sourceFileIdentity?.deleteIfUnchanged()
        completeTerminalOnQueue(.completed(videoInfo))
    }

    private func requestCancellation() {
        stateQueue.async { [weak self] in
            self?.cancelOnQueue()
        }
    }

    private func cancelOnQueue() {
        guard !isTerminal else { return }
        guard task.claimCancellationTerminalOutcome() else { return }
        if let prepared = configuration {
            cancelReadingOnQueue(prepared)
            if prepared.writer.status == .writing {
                prepared.writer.cancelWriting()
            }
        }
        progress?.cancelWriting()
        removePartialOutputOnQueue()
        completeTerminalOnQueue(.cancelled)
    }

    private func failOnQueue(
        _ error: Error,
        taskOutcomeAlreadyClaimed: Bool = false
    ) {
        guard !isTerminal else { return }
        let terminalState: CompressionState
        if taskOutcomeAlreadyClaimed {
            terminalState = .failed(error)
        } else {
            switch task.claimFailureTerminalOutcome() {
            case .failure:
                terminalState = .failed(error)
            case .cancellation:
                terminalState = .cancelled
            case .unavailable:
                return
            }
        }
        if let prepared = configuration {
            cancelReadingOnQueue(prepared)
            if prepared.writer.status == .writing {
                prepared.writer.cancelWriting()
            }
        }
        progress?.cancelWriting()
        removePartialOutputOnQueue()
        completeTerminalOnQueue(terminalState)
    }

    private func finishPreparation(with error: Error) {
        let failure = VideoConversionFailure(error)
        stateQueue.async { [weak self, failure] in
            self?.failOnQueue(failure.error)
        }
    }

    private func removePartialOutputOnQueue() {
        configuration?.outputTransaction.discard()
    }

    private func completeTerminalOnQueue(_ state: CompressionState) {
        guard !isTerminal else { return }
        isTerminal = true
        task.removeCancellationHandler(cancellationHandlerID)
        cancellationHandlerID = nil

        // Release AVFoundation state and the destination reservation before
        // entering caller code. A terminal callback is allowed to block or
        // immediately start another conversion for the same destination.
        pumps.removeAll()
        configuration = nil
        progress = nil
        retainedSession = nil
        callbackDelivery.enqueue(state)
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
    let outputTransaction: FileOutputTransaction
    let sourceFileIdentity: SourceFileIdentity?

    init(
        asset: AVAsset,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        video: VideoVariables,
        audio: AudioVariables,
        metadata: MetadataVariables,
        outputTransaction: FileOutputTransaction,
        sourceFileIdentity: SourceFileIdentity?
    ) {
        self.asset = asset
        self.reader = reader
        self.writer = writer
        self.video = video
        self.audio = audio
        self.metadata = metadata
        self.outputTransaction = outputTransaction
        self.sourceFileIdentity = sourceFileIdentity
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
    let sampleHandler: ((CMSampleBuffer, CVPixelBufferPool?) -> VideoSampleProcessingOutput)?
    let readsAsynchronously: Bool
    var isFinished = false
    var isProcessing = false
    private var pendingSamples: [CMSampleBuffer] = []

    init(
        kind: VideoTrackKind,
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        sampleHandler: ((CMSampleBuffer, CVPixelBufferPool?) -> VideoSampleProcessingOutput)? = nil,
        readsAsynchronously: Bool = false
    ) {
        self.kind = kind
        self.input = input
        self.output = output
        self.sampleHandler = sampleHandler
        self.readsAsynchronously = readsAsynchronously
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

private final class VideoSampleProcessingWork: @unchecked Sendable {
    private let sample: CMSampleBuffer
    private let pixelBufferPool: CVPixelBufferPool?
    private let handler: (CMSampleBuffer, CVPixelBufferPool?) -> VideoSampleProcessingOutput

    init(
        sample: CMSampleBuffer,
        pixelBufferPool: CVPixelBufferPool?,
        handler: @escaping (CMSampleBuffer, CVPixelBufferPool?) -> VideoSampleProcessingOutput
    ) {
        self.sample = sample
        self.pixelBufferPool = pixelBufferPool
        self.handler = handler
    }

    func run() -> VideoSampleProcessingResult {
        VideoSampleProcessingResult(
            sourceSample: sample,
            output: handler(sample, pixelBufferPool)
        )
    }
}

private final class VideoSampleReadWork: @unchecked Sendable {
    private let output: AVAssetReaderOutput

    init(output: AVAssetReaderOutput) {
        self.output = output
    }

    func run() -> VideoSampleReadResult {
        VideoSampleReadResult(sample: output.copyNextSampleBuffer())
    }
}

private final class VideoSampleReadResult: @unchecked Sendable {
    let sample: CMSampleBuffer?

    init(sample: CMSampleBuffer?) {
        self.sample = sample
    }
}

private final class VideoSampleProcessingResult: @unchecked Sendable {
    let sourceSample: CMSampleBuffer
    let output: VideoSampleProcessingOutput

    init(sourceSample: CMSampleBuffer, output: VideoSampleProcessingOutput) {
        self.sourceSample = sourceSample
        self.output = output
    }
}
