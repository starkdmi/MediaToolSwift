@preconcurrency import AVFoundation
import Foundation

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// The immutable request data retained by a single audio conversion.
///
/// This type intentionally remains internal. `AVMetadataItem` and the legacy callback
/// are not safe general-purpose concurrency values, so they are kept within the
/// serial conversion session rather than being published as `Sendable` data.
internal struct AudioConversionRequest {
    let source: URL
    let destination: URL
    let fileType: AudioFileType
    let settings: CompressionAudioSettings?
    let edit: Set<AudioOperation>
    let skipSourceMetadata: Bool
    let customMetadata: [AVMetadataItem]
    let copyExtendedFileMetadata: Bool
    let cacheDirectory: URL?
    let overwrite: Bool
    let deleteSourceFile: Bool
    let progressQueue: DispatchQueue
    let callback: (CompressionState) -> Void
}

/// All AVFoundation state for one audio conversion.
///
/// `AVAssetReader`, `AVAssetWriter`, their inputs/outputs, and terminal state are
/// accessed only from `queue` after the one-time setup handoff. The class is marked
/// `@unchecked Sendable` solely so cancellation and AVFoundation callbacks can
/// enqueue work back onto that serial queue; those callbacks never capture an AV
/// object or `CompressionTask` independently.
internal final class AudioConversionSession: @unchecked Sendable {
    private enum TerminalEvent {
        case completed(AudioInfo)
        case cancelled
        case failed(Error)
    }

    private struct PreparedState {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let output: AVAssetReaderOutput
        let metadata: [AVMetadataItem]
        let duration: CMTime
        let timeRange: CMTimeRange?
        let codec: CompressionAudioCodec
        let bitrate: Int?
        let destinationExisted: Bool
    }

    private struct ProgressState {
        var total: Int64 = 100
        var completed: Int64 = 0
        var startedAt: Date?
        var isTerminal = false
        var completedSuccessfully = false
    }

    private let request: AudioConversionRequest
    private let task: CompressionTask
    private let queue = DispatchQueue(label: "MediaToolSwift.audio.conversion")
    private let progressLock = NSLock()

    // These values are installed before `queue` first receives work, then owned by
    // that queue for the rest of the conversion.
    private var preparedState: PreparedState?
    private var pendingTerminalEvent: TerminalEvent?

    // Queue-isolated state.
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var output: AVAssetReaderOutput?
    private var duration: CMTime = .zero
    private var timeRange: CMTimeRange?
    private var codec: CompressionAudioCodec = .default
    private var bitrate: Int?
    private var destinationExisted = false
    private var replacedExistingDestination = false
    private var didAttemptWriting = false
    private var isFinishing = false
    private var didFinish = false
    private var cancellationHandlerID: UUID?
    private var retainedUntilTerminal: AudioConversionSession?

    private var progressState = ProgressState()

    init(request: AudioConversionRequest, task: CompressionTask) {
        self.request = request
        self.task = task
    }

    /// Performs async asset loading before handing the configured AV objects to the
    /// session queue. The caller cannot observe the task until this method returns,
    /// so no other thread can access the pre-start state.
    func prepareAndStart() async {
        do {
            // Record whether the caller already owns a destination before any
            // validation can fail. Terminal cleanup uses this to avoid deleting
            // that existing file on an early error.
            queue.sync {
                destinationExisted = FileManager.default.fileExists(atPath: request.destination.path)
            }
            preparedState = try await makePreparedState()
            queue.async { [self] in
                retainedUntilTerminal = self
                startOnQueue()
            }
        } catch {
            if task.isCancelled {
                queue.async { [self] in
                    retainedUntilTerminal = self
                    cancelOnQueue()
                }
            } else {
                pendingTerminalEvent = .failed(error)
                queue.async { [self] in
                    retainedUntilTerminal = self
                    deliverPendingTerminalEventOnQueue()
                }
            }
        }
    }

    private func makePreparedState() async throws -> PreparedState {
        guard FileManager.default.fileExists(atPath: request.source.path) else {
            throw CompressionError.sourceFileNotFound
        }

        guard request.destination.pathExtension.lowercased() == request.fileType.rawValue else {
            throw CompressionError.invalidFileType
        }

        let destinationExisted = FileManager.default.fileExists(atPath: request.destination.path)
        guard !destinationExisted || request.overwrite else {
            throw CompressionError.destinationFileExists
        }

        // AVAssetWriter cannot safely replace its own source. More importantly, do
        // not remove the caller's source file while preparing an overwrite.
        guard request.source.standardizedFileURL != request.destination.standardizedFileURL else {
            throw CompressionError.cannotOverWrite
        }

        let asset = AVAsset(url: request.source)
        guard let track = await asset.getFirstTrack(withMediaType: .audio) else {
            throw CompressionError.audioTrackNotFound
        }
        let variables = try await AudioTrackConfiguration.makeVariables(
            track: track,
            settings: request.settings
        )
        guard !variables.skipAudio,
              let input = variables.audioInput,
              let output = variables.audioOutput else {
            throw CompressionError.audioTrackNotFound
        }

        let assetDuration = await asset.getDuration()
        let (duration, timeRange) = applyAudioEditOperations(request.edit, duration: assetDuration)
        guard variables.hasChanges || timeRange != nil else {
            throw CompressionError.redundantCompression
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: request.destination, fileType: request.fileType.value)
        writer.directoryForTemporaryFiles = request.cacheDirectory

        let metadata = await makeMetadata(asset: asset)
        return PreparedState(
            reader: reader,
            writer: writer,
            input: input,
            output: output,
            metadata: metadata,
            duration: duration,
            timeRange: timeRange,
            codec: variables.codec ?? .default,
            bitrate: variables.bitrate,
            destinationExisted: destinationExisted
        )
    }

    private func makeMetadata(asset: AVAsset) async -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []
        if !request.skipSourceMetadata {
            metadata = await asset.getMetadata()
            var commonMetadata: [AVMetadataItem] = []

            for item in metadata {
                guard let key = item.commonKey else { continue }

                let commonItem = AVMutableMetadataItem()
                commonItem.key = key as NSString
                commonItem.keySpace = .common
                commonItem.value = await item.getValue()
                commonItem.dataType = item.dataType
                commonMetadata.append(commonItem)
            }
            metadata.append(contentsOf: commonMetadata)
        }

        metadata.append(contentsOf: request.customMetadata)
        return metadata
    }

    private func startOnQueue() {
        if let event = pendingTerminalEvent {
            pendingTerminalEvent = nil
            finishOnQueue(event)
            return
        }

        guard let preparedState else {
            finishOnQueue(.failed(CompressionError.failedToReadAudio))
            return
        }

        reader = preparedState.reader
        writer = preparedState.writer
        input = preparedState.input
        output = preparedState.output
        let metadata = preparedState.metadata
        duration = preparedState.duration
        timeRange = preparedState.timeRange
        codec = preparedState.codec
        bitrate = preparedState.bitrate
        destinationExisted = preparedState.destinationExisted
        self.preparedState = nil

        cancellationHandlerID = task.registerCancellationHandler { [weak self] in
            self?.enqueueCancellation()
        }

        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }

        guard let reader, let writer, let input, let output else {
            finishOnQueue(.failed(CompressionError.audioTrackNotFound))
            return
        }

        guard reader.canAdd(output) else {
            finishOnQueue(.failed(CompressionError.failedToReadAudio))
            return
        }
        reader.add(output)

        do {
            try addInput(input, to: writer)
        } catch {
            finishOnQueue(.failed(error))
            return
        }

        if !metadata.isEmpty {
            writer.metadata = metadata
        }

        if destinationExisted {
            do {
                try FileManager.default.removeItem(at: request.destination)
                replacedExistingDestination = true
            } catch {
                finishOnQueue(.failed(CompressionError.cannotOverWrite))
                return
            }
        }

        if let timeRange {
            reader.timeRange = timeRange
        }

        guard reader.startReading() else {
            finishOnQueue(.failed(reader.error ?? CompressionError.failedToReadAudio))
            return
        }

        didAttemptWriting = true
        guard writer.startWriting() else {
            finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
            return
        }

        writer.startSession(atSourceTime: timeRange?.start ?? .zero)
        configureProgressOnQueue()
        request.callback(.started)

        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.drainSamplesOnQueue()
        }
    }

    private func addInput(_ input: AVAssetWriterInput, to writer: AVAssetWriter) throws {
        #if canImport(ObjCExceptionCatcher)
        try ObjCExceptionCatcher.catchException {
            writer.add(input)
        }
        #else
        guard writer.canAdd(input) else {
            throw CompressionError.failedToWriteAudio
        }
        writer.add(input)
        #endif
    }

    private func drainSamplesOnQueue() {
        guard !didFinish,
              !isFinishing,
              let reader,
              let writer,
              let input,
              let output else {
            return
        }

        if task.isCancelled {
            cancelOnQueue()
            return
        }

        var processedSamples = 0
        while input.isReadyForMoreMediaData, processedSamples < 8 {
            if task.isCancelled {
                cancelOnQueue()
                return
            }

            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    finishOnQueue(.failed(reader.error ?? CompressionError.failedToReadAudio))
                } else if reader.status == .cancelled {
                    cancelOnQueue()
                } else {
                    input.markAsFinished()
                    finishWritingOnQueue()
                }
                return
            }

            guard input.append(sample) else {
                finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
                return
            }

            recordProgressOnQueue(for: sample)
            processedSamples += 1
        }

        // Yield after a bounded batch so an enqueued cancellation can run even
        // when AVFoundation keeps the input continuously ready for data.
        if input.isReadyForMoreMediaData, !didFinish, !isFinishing {
            queue.async { [weak self] in
                self?.drainSamplesOnQueue()
            }
        }
    }

    private func finishWritingOnQueue() {
        guard !didFinish, !isFinishing, let reader, let writer else { return }
        isFinishing = true
        reader.cancelReading()
        writer.finishWriting { [weak self] in
            self?.queue.async { [weak self] in
                self?.completeWritingOnQueue()
            }
        }
    }

    private func completeWritingOnQueue() {
        guard !didFinish, let writer else { return }

        if task.isCancelled || writer.status == .cancelled {
            cancelOnQueue()
            return
        }

        guard writer.status == .completed,
              FileManager.default.fileExists(atPath: request.destination.path) else {
            finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
            return
        }

        var extendedInfo: ExtendedFileInfo?
        if request.copyExtendedFileMetadata {
            let data = FileExtendedAttributes.copyExtendedMetadata(
                from: request.source.path,
                to: request.destination.path,
                customAttributes: [:]
            )
            extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: data)
        }

        guard task.claimSuccessfulTerminalOutcome() else {
            cancelOnQueue()
            return
        }

        if request.deleteSourceFile {
            try? FileManager.default.removeItem(at: request.source)
        }

        finishOnQueue(.completed(AudioInfo(
            url: writer.outputURL,
            duration: duration.seconds,
            codec: codec,
            bitrate: bitrate,
            extendedInfo: extendedInfo
        )))
    }

    private func enqueueCancellation() {
        queue.async { [weak self] in
            self?.cancelOnQueue()
        }
    }

    private func cancelOnQueue() {
        guard !didFinish else { return }

        // `markAsFinished()` is only valid after the writer enters `.writing`.
        // Immediate cancellation can arrive while the session is still being
        // configured, before `startWriting()` has succeeded.
        if writer?.status == .writing {
            input?.markAsFinished()
        }
        reader?.cancelReading()
        writer?.cancelWriting()
        finishOnQueue(.cancelled)
    }

    private func deliverPendingTerminalEventOnQueue() {
        guard let event = pendingTerminalEvent else { return }
        pendingTerminalEvent = nil
        finishOnQueue(event)
    }

    private func finishOnQueue(_ event: TerminalEvent) {
        guard !didFinish else { return }
        didFinish = true
        task.markTerminalOutcome()
        task.removeCancellationHandler(cancellationHandlerID)

        switch event {
        case .completed:
            setTerminalProgressOnQueue(completedSuccessfully: true)
        case .cancelled, .failed:
            reader?.cancelReading()
            writer?.cancelWriting()
            removePartialOutputOnQueue()
            setTerminalProgressOnQueue(completedSuccessfully: false)
        }

        request.callback({
            switch event {
            case .completed(let info):
                return .completed(info)
            case .cancelled:
                return .cancelled
            case .failed(let error):
                return .failed(error)
            }
        }())

        retainedUntilTerminal = nil
    }

    private func removePartialOutputOnQueue() {
        // Preserve an existing destination until this session has successfully
        // replaced it. A failed reader/input configuration must never delete a
        // caller's pre-existing file.
        guard !destinationExisted || replacedExistingDestination || didAttemptWriting else {
            return
        }
        try? FileManager.default.removeItem(at: request.destination)
    }

    private func configureProgressOnQueue() {
        let seconds = duration.seconds
        let finiteSeconds = seconds.isFinite ? max(seconds, 0) : 0
        let total = max(Int64(ceil(finiteSeconds * 0.05)), 100)

        progressLock.lock()
        progressState.total = total
        progressState.completed = 0
        progressState.startedAt = Date()
        progressState.isTerminal = false
        progressState.completedSuccessfully = false
        progressLock.unlock()

        enqueueProgressDelivery()
    }

    private func recordProgressOnQueue(for sample: CMSampleBuffer) {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return }

        let offset = timeRange?.start.seconds ?? 0
        let elapsed = max(sample.presentationTimeStamp.seconds - offset, 0)
        let percentage = min(max(elapsed / seconds, 0), 1)

        progressLock.lock()
        let completed = Int64(percentage * Double(progressState.total))
        let changed = completed > progressState.completed
        if changed {
            progressState.completed = completed
        }
        progressLock.unlock()

        if changed {
            enqueueProgressDelivery()
        }
    }

    private func setTerminalProgressOnQueue(completedSuccessfully: Bool) {
        progressLock.lock()
        progressState.isTerminal = true
        progressState.completedSuccessfully = completedSuccessfully
        if completedSuccessfully {
            progressState.completed = progressState.total
        }
        progressLock.unlock()

        enqueueProgressDelivery()
    }

    private func enqueueProgressDelivery() {
        request.progressQueue.async { [self] in
            deliverProgress()
        }
    }

    private func deliverProgress() {
        progressLock.lock()
        let state = progressState
        progressLock.unlock()

        let progress = task.progress
        if progress.totalUnitCount != state.total {
            progress.totalUnitCount = state.total
        }
        if state.completed > progress.completedUnitCount {
            progress.completedUnitCount = state.completed
        }

        if state.isTerminal {
            if state.completedSuccessfully {
                progress.completedUnitCount = state.total
            }
            progress.estimatedTimeRemaining = nil
        } else if let startedAt = state.startedAt,
                  let remaining = progress.estimateRemainingTime(startedAt: startedAt, offset: 0.05) {
            progress.estimatedTimeRemaining = remaining
        }
    }
}

// MARK: - Shared Audio Helpers

/// Applies edit operations and returns the resulting duration and source range.
internal func applyAudioEditOperations(
    _ edit: Set<AudioOperation>,
    duration: CMTime
) -> (duration: CMTime, timeRange: CMTimeRange?) {
    var finalDuration = duration
    var timeRange: CMTimeRange?

    for operation in edit {
        guard case let .cut(from: start, to: end) = operation, timeRange == nil else {
            continue
        }
        guard let range = CMTimeRange(
            start: start,
            end: end,
            duration: duration.seconds,
            timescale: duration.timescale
        ) else {
            continue
        }
        timeRange = range
        finalDuration = range.duration
    }

    return (finalDuration, timeRange)
}
