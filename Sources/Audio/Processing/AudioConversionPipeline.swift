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

private struct AudioProgressSnapshot {
    var total: Int64 = 100
    var completed: Int64 = 0
    var startedAt: Date?
    var isTerminal = false
    var completedSuccessfully = false
}

/// Coalesces progress snapshots without retaining the AV conversion session on
/// a caller-provided queue. A suspended queue may retain this lightweight owner
/// and the public task, but never a reader, writer, callback, or source asset.
private final class AudioProgressDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private let task: CompressionTask
    private let queue: DispatchQueue
    private var snapshot = AudioProgressSnapshot()
    private var isScheduled = false

    init(task: CompressionTask, targetQueue: DispatchQueue) {
        self.task = task
        queue = DispatchQueue(
            label: "MediaToolSwift.audio.progress",
            target: targetQueue
        )
    }

    func enqueue(_ snapshot: AudioProgressSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        guard !isScheduled else {
            lock.unlock()
            return
        }
        isScheduled = true
        lock.unlock()

        queue.async { [self] in
            deliverLatest()
        }
    }

    private func deliverLatest() {
        lock.lock()
        let snapshot = self.snapshot
        isScheduled = false
        lock.unlock()

        let progress = task.progress
        if progress.totalUnitCount != snapshot.total {
            progress.totalUnitCount = snapshot.total
        }
        if snapshot.completed > progress.completedUnitCount {
            progress.completedUnitCount = snapshot.completed
        }

        if snapshot.isTerminal {
            if snapshot.completedSuccessfully {
                progress.completedUnitCount = snapshot.total
            }
            progress.estimatedTimeRemaining = nil
        } else if let startedAt = snapshot.startedAt,
                  let remaining = progress.estimateRemainingTime(startedAt: startedAt, offset: 0.05) {
            progress.estimatedTimeRemaining = remaining
        }
    }
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
        let outputTransaction: FileOutputTransaction
        let sourceFileIdentity: SourceFileIdentity?
    }

    private let request: AudioConversionRequest
    private let task: CompressionTask
    private let queue = DispatchQueue(label: "MediaToolSwift.audio.conversion")
    private let progressDelivery: AudioProgressDelivery
    private let callbackDelivery: LegacyCallbackDelivery<CompressionState>

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
    private var outputTransaction: FileOutputTransaction?
    private var sourceFileIdentity: SourceFileIdentity?
    private var isFinishing = false
    private var didFinish = false
    private var cancellationHandlerID: UUID?
    private var retainedUntilTerminal: AudioConversionSession?

    private var progressState = AudioProgressSnapshot()

    init(request: AudioConversionRequest, task: CompressionTask) {
        self.request = request
        self.task = task
        progressDelivery = AudioProgressDelivery(
            task: task,
            targetQueue: request.progressQueue
        )
        callbackDelivery = LegacyCallbackDelivery(
            label: "MediaToolSwift.audio.callback",
            callback: request.callback
        )
    }

    /// Performs async asset loading before handing the configured AV objects to the
    /// session queue. The caller cannot observe the task until this method returns,
    /// so no other thread can access the pre-start state.
    func prepareAndStart() async {
        do {
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
        guard !task.isCancelled, !Task.isCancelled else {
            throw CancellationError()
        }
        guard FileManager.default.fileExists(atPath: request.source.path) else {
            throw CompressionError.sourceFileNotFound
        }
        let sourceFileIdentity = request.deleteSourceFile
            ? SourceFileIdentity(at: request.source)
            : nil

        guard request.destination.pathExtension.lowercased() == request.fileType.rawValue else {
            throw CompressionError.invalidFileType
        }

        // AVAssetWriter cannot safely replace its own source. More importantly, do
        // not remove the caller's source file while preparing an overwrite.
        guard !fileURLsReferToSameItem(request.source, request.destination) else {
            throw CompressionError.cannotOverWrite
        }
        let outputTransaction = try FileOutputTransaction(
            destination: request.destination,
            overwrite: request.overwrite
        )

        let asset = AVAsset(url: request.source)
        guard let track = await asset.getFirstTrack(withMediaType: .audio) else {
            throw CompressionError.audioTrackNotFound
        }
        let variables = try await AudioTrackConfiguration.makeVariables(
            track: track,
            settings: request.settings
        )
        guard !task.isCancelled, !Task.isCancelled else {
            outputTransaction.discard()
            throw CancellationError()
        }
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
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(
                outputURL: outputTransaction.outputURL,
                fileType: request.fileType.value
            )
            outputTransaction.captureOutputIdentityIfPresent()
        } catch {
            outputTransaction.discard()
            throw error
        }
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
            outputTransaction: outputTransaction,
            sourceFileIdentity: sourceFileIdentity
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
        outputTransaction = preparedState.outputTransaction
        sourceFileIdentity = preparedState.sourceFileIdentity
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

        if let timeRange {
            reader.timeRange = timeRange
        }

        guard reader.startReading() else {
            finishOnQueue(.failed(reader.error ?? CompressionError.failedToReadAudio))
            return
        }

        let didStartWriting = writer.startWriting()
        outputTransaction?.captureOutputIdentityIfPresent()
        guard didStartWriting else {
            finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
            return
        }

        writer.startSession(atSourceTime: timeRange?.start ?? .zero)
        configureProgressOnQueue()
        callbackDelivery.enqueue(.started) { [weak self] in
            self?.queue.async { [weak self] in
                self?.startPumpingAfterStartedOnQueue()
            }
        }
    }

    private func startPumpingAfterStartedOnQueue() {
        guard !didFinish, !isFinishing, let input else { return }
        guard !task.isCancelled else {
            cancelOnQueue()
            return
        }
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
                    guard markInputFinishedOnQueue(input, writer: writer) else { return }
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
        if reader.status == .reading {
            reader.cancelReading()
        }
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
              let outputTransaction,
              FileManager.default.fileExists(atPath: outputTransaction.outputURL.path) else {
            finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
            return
        }

        var extendedInfo: ExtendedFileInfo?
        if request.copyExtendedFileMetadata {
            let data = FileExtendedAttributes.copyExtendedMetadata(
                from: request.source.path,
                to: outputTransaction.outputURL.path,
                customAttributes: [:]
            )
            extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: data)
        }

        guard task.claimSuccessfulTerminalOutcome() else {
            cancelOnQueue()
            return
        }

        do {
            try outputTransaction.commit()
        } catch {
            finishOnQueue(.failed(error), taskOutcomeAlreadyClaimed: true)
            return
        }

        sourceFileIdentity?.deleteIfUnchanged()

        finishOnQueue(.completed(AudioInfo(
            url: request.destination,
            duration: duration.seconds,
            codec: codec,
            bitrate: bitrate,
            extendedInfo: extendedInfo
        )), taskOutcomeAlreadyClaimed: true)
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
        if !isFinishing, let input, let writer, writer.status == .writing {
            _ = markInputFinishedOnQueue(input, writer: writer)
        }
        if reader?.status == .reading {
            reader?.cancelReading()
        }
        if writer?.status == .writing {
            writer?.cancelWriting()
        }
        finishOnQueue(.cancelled)
    }

    private func deliverPendingTerminalEventOnQueue() {
        guard let event = pendingTerminalEvent else { return }
        pendingTerminalEvent = nil
        finishOnQueue(event)
    }

    private func finishOnQueue(
        _ requestedEvent: TerminalEvent,
        taskOutcomeAlreadyClaimed: Bool = false
    ) {
        guard !didFinish else { return }
        let event: TerminalEvent
        if taskOutcomeAlreadyClaimed {
            event = requestedEvent
        } else {
            switch requestedEvent {
            case .completed:
                guard task.claimSuccessfulTerminalOutcome() else {
                    cancelOnQueue()
                    return
                }
                event = requestedEvent
            case .cancelled:
                guard task.claimCancellationTerminalOutcome() else { return }
                event = .cancelled
            case .failed(let error):
                switch task.claimFailureTerminalOutcome() {
                case .failure:
                    event = .failed(error)
                case .cancellation:
                    event = .cancelled
                case .unavailable:
                    return
                }
            }
        }

        didFinish = true
        task.removeCancellationHandler(cancellationHandlerID)

        switch event {
        case .completed:
            setTerminalProgressOnQueue(completedSuccessfully: true)
        case .cancelled, .failed:
            if reader?.status == .reading {
                reader?.cancelReading()
            }
            if writer?.status == .writing {
                writer?.cancelWriting()
            }
            removePartialOutputOnQueue()
            setTerminalProgressOnQueue(completedSuccessfully: false)
        }

        let callbackState: CompressionState = {
            switch event {
            case .completed(let info):
                return .completed(info)
            case .cancelled:
                return .cancelled
            case .failed(let error):
                return .failed(error)
            }
        }()

        // Drop the conversion's AV state and destination reservation before
        // entering caller code. Terminal callbacks may block or immediately
        // start a follow-up conversion for the same destination.
        reader = nil
        writer = nil
        input = nil
        output = nil
        outputTransaction = nil
        sourceFileIdentity = nil
        preparedState = nil
        retainedUntilTerminal = nil
        callbackDelivery.enqueue(callbackState)
    }

    private func markInputFinishedOnQueue(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter
    ) -> Bool {
        guard writer.status == .writing else {
            finishOnQueue(.failed(writer.error ?? CompressionError.failedToWriteAudio))
            return false
        }

        do {
            #if canImport(ObjCExceptionCatcher)
            try ObjCExceptionCatcher.catchException {
                input.markAsFinished()
            }
            #else
            input.markAsFinished()
            #endif
            return true
        } catch {
            finishOnQueue(.failed(error))
            return false
        }
    }

    private func removePartialOutputOnQueue() {
        outputTransaction?.discard()
    }

    private func configureProgressOnQueue() {
        let seconds = duration.seconds
        let finiteSeconds = seconds.isFinite ? max(seconds, 0) : 0
        let maximumConvertibleValue = Double(Int64.max).nextDown
        let scaledSeconds = ceil(finiteSeconds * 0.05)
        let boundedTotal = min(scaledSeconds, maximumConvertibleValue)
        let total = max(Int64(boundedTotal), 100)

        progressState.total = total
        progressState.completed = 0
        progressState.startedAt = Date()
        progressState.isTerminal = false
        progressState.completedSuccessfully = false

        enqueueProgressDelivery()
    }

    private func recordProgressOnQueue(for sample: CMSampleBuffer) {
        guard let completed = audioProgressCompletedUnitCount(
            sampleTime: sample.presentationTimeStamp,
            duration: duration,
            range: timeRange,
            total: progressState.total
        ) else {
            return
        }
        let changed = completed > progressState.completed
        if changed {
            progressState.completed = completed
        }

        if changed {
            enqueueProgressDelivery()
        }
    }

    private func setTerminalProgressOnQueue(completedSuccessfully: Bool) {
        progressState.isTerminal = true
        progressState.completedSuccessfully = completedSuccessfully
        if completedSuccessfully {
            progressState.completed = progressState.total
        }

        enqueueProgressDelivery()
    }

    private func enqueueProgressDelivery() {
        progressDelivery.enqueue(progressState)
    }
}

// MARK: - Shared Audio Helpers

/// Maps a sample timestamp to a bounded progress count. Malformed media can
/// carry invalid or non-finite `CMTime` values; reject those before converting
/// the resulting percentage to `Int64`.
internal func audioProgressCompletedUnitCount(
    sampleTime: CMTime,
    duration: CMTime,
    range: CMTimeRange?,
    total: Int64
) -> Int64? {
    let seconds = duration.seconds
    let offset = range?.start.seconds ?? 0
    let sampleSeconds = sampleTime.seconds
    guard seconds.isFinite, seconds > 0,
          offset.isFinite, sampleSeconds.isFinite,
          total >= 0 else {
        return nil
    }

    let elapsed = max(sampleSeconds - offset, 0)
    let percentage = min(max(elapsed / seconds, 0), 1)
    guard percentage.isFinite else { return nil }
    return percentage == 1
        ? total
        : Int64(percentage * Double(total))
}

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
