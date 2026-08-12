import AVFoundation
import Foundation

/// Queue-confined progress reporting for one video conversion.
///
/// `Progress` and file-system observers are reference types without Sendable
/// contracts. This owner serializes every access to them on a private queue.
internal final class CompressionVideoProgress: @unchecked Sendable {
    private let queue: DispatchQueue

    private let task: CompressionTask
    private let total: Double
    private let totalSteps: Int64
    private let frameDuration: Double
    private let timeOffset: Double
    private let duration: Double
    private let startTime: Double

    private let useWritingProgress: Bool
    private var writingInitialized = false
    private var writingTotal: Int64
    private var configuredWritingProgress: Progress?
    private var acceptsWritingUpdates = true
    private let fileURL: URL
    private let observedOutputURL: URL
    private var observer: FileSizeObserver?

    private let startedTime: Date

    /// Progress objects remain publicly replaceable for source compatibility.
    /// Resolve them only on this queue so a replacement participates in later
    /// updates instead of leaving the conversion bound to stale instances.
    private var progress: Progress { task.progress }
    private var writingProgress: Progress { task.writingProgress }

    internal init(
        task: CompressionTask,
        timeRange: CMTimeRange,
        estimatedFileLengthInKB: Double,
        frameRate: Float?,
        destination: URL,
        observedOutput: URL,
        queue progressQueue: DispatchQueue,
        config: FileObserverConfig
    ) {
        queue = DispatchQueue(
            label: "MediaToolSwift.video.progress",
            qos: .userInteractive,
            target: progressQueue
        )
        self.task = task
        startedTime = Date()
        fileURL = destination
        observedOutputURL = observedOutput

        startTime = timeRange.start.seconds
        duration = timeRange.duration.seconds
        if let frameRate, frameRate > 0 {
            frameDuration = 1.0 / Double(frameRate)
        } else {
            frameDuration = 0.0
        }

        let minimumSteps: Int64 = 100
        let scaleFactor = 0.5
        let scaledSteps = duration.isFinite ? max(ceil(duration * scaleFactor), 0) : 0
        let maximumConvertibleInt64 = Double(Int64.max).nextDown
        let boundedSteps = min(scaledSteps, maximumConvertibleInt64)
        let totalSteps = max(Int64(boundedSteps), minimumSteps)
        total = Double(totalSteps)
        self.totalSteps = totalSteps
        let estimatedBytes = estimatedFileLengthInKB * 1024
        if estimatedBytes.isFinite, estimatedBytes > 0 {
            writingTotal = Int64(min(estimatedBytes, maximumConvertibleInt64))
        } else {
            writingTotal = 0
        }

        switch estimatedFileLengthInKB {
        case 0 ... 10_000:
            timeOffset = 0.1
        case 10_000 ... 25_000:
            timeOffset = 0.05
        case 25_000 ... 50_000:
            timeOffset = 0.03
        default:
            timeOffset = 0.01
        }

        if estimatedFileLengthInKB < FileObserverConfig.minimalFileLenght {
            useWritingProgress = false
        } else {
            useWritingProgress = config == .matching
        }

        queue.async { [self] in
            _ = self.configuredEncodingProgress()
            if self.useWritingProgress,
               FileManager.default.fileExists(atPath: observedOutput.path) {
                self.initializeWriting()
            }
        }
    }

    /// Update encoding progress with a sample presentation timestamp.
    internal func update(_ timeStamp: CMTime) {
        let currentTime = timeStamp.seconds + frameDuration - startTime
        let percentage = currentTime / duration
        guard percentage.isFinite else { return }

        queue.async { [self] in
            self.updateEncoding(percentage: percentage)
        }
    }

    /// Finish encoding progress.
    internal func complete() {
        queue.async { [self] in
            let progress = self.configuredEncodingProgress()
            if progress.completedUnitCount != progress.totalUnitCount {
                progress.completedUnitCount = progress.totalUnitCount
            }
            progress.estimatedTimeRemaining = nil
        }
    }

    /// Finish writing/saving progress.
    internal func completeWriting() {
        queue.async { [self] in
            acceptsWritingUpdates = false
            self.stopObservingWriting()
            let writingProgress = self.writingProgress
            if self.useWritingProgress {
                self.configureWritingProgress(writingProgress)
                if writingProgress.totalUnitCount != writingProgress.completedUnitCount {
                    writingProgress.totalUnitCount = writingProgress.completedUnitCount
                }
                writingProgress.estimatedTimeRemaining = nil
                #if os(macOS)
                writingProgress.unpublish()
                #endif
            } else {
                writingProgress.completedUnitCount = 1
                writingProgress.totalUnitCount = 1
            }
        }
    }

    /// Clear writing progress after cancellation or failure.
    internal func cancelWriting() {
        queue.async { [self] in
            acceptsWritingUpdates = false
            self.stopObservingWriting()
            let writingProgress = self.writingProgress
            if self.useWritingProgress {
                self.configureWritingProgress(writingProgress)
                writingProgress.estimatedTimeRemaining = nil
                writingProgress.totalUnitCount = -1
                writingProgress.completedUnitCount = 0
            }
            #if os(macOS)
            writingProgress.unpublish()
            #endif
        }
    }

    private func updateEncoding(percentage: Double) {
        let progress = configuredEncodingProgress()
        let boundedPercentage = min(max(percentage, 0), 1)
        let completedUnitCount = boundedPercentage == 1
            ? totalSteps
            : Int64(boundedPercentage * total)

        guard completedUnitCount > progress.completedUnitCount else { return }
        progress.completedUnitCount = completedUnitCount

        if let remaining = progress.estimateRemainingTime(
            startedAt: startedTime,
            offset: timeOffset
        ) {
            progress.estimatedTimeRemaining = remaining
        }

        if useWritingProgress, progress.fractionCompleted > timeOffset {
            initializeWriting()
        }
    }

    private func configuredEncodingProgress() -> Progress {
        let progress = self.progress
        if progress.totalUnitCount != totalSteps {
            progress.totalUnitCount = totalSteps
        }
        return progress
    }

    private func configureWritingProgress(_ writingProgress: Progress) {
        guard configuredWritingProgress !== writingProgress else { return }

        #if os(macOS)
        configuredWritingProgress?.unpublish()
        #endif

        configuredWritingProgress = writingProgress
        writingProgress.fileURL = fileURL
        guard useWritingProgress else { return }

        writingProgress.kind = .file
        writingProgress.totalUnitCount = writingTotal
        #if os(macOS)
        writingProgress.publish()
        #endif
    }

    private func initializeWriting() {
        guard acceptsWritingUpdates else { return }
        let writingProgress = self.writingProgress
        configureWritingProgress(writingProgress)
        guard !writingInitialized else { return }
        writingInitialized = true

        let observerQueue = DispatchQueue(label: "MediaToolSwift.video.file-size")
        observer = FileSizeObserver(url: observedOutputURL, queue: observerQueue) { [weak self] fileSize in
            self?.queue.async { [weak self] in
                guard let self, self.acceptsWritingUpdates else { return }
                self.updateWriting(fileSize: Int64(fileSize))
            }
        }
    }

    private func updateWriting(fileSize: Int64) {
        guard acceptsWritingUpdates else { return }
        let writingProgress = self.writingProgress
        configureWritingProgress(writingProgress)
        guard fileSize < writingProgress.totalUnitCount else {
            writingProgress.totalUnitCount = fileSize + 1
            writingProgress.completedUnitCount = fileSize
            writingProgress.estimatedTimeRemaining = nil
            return
        }

        guard fileSize > writingProgress.completedUnitCount + FileObserverConfig.threshold ||
                writingProgress.completedUnitCount == 0 else {
            return
        }

        writingProgress.completedUnitCount = fileSize
        if let remaining = writingProgress.estimateRemainingTime(
            startedAt: startedTime,
            offset: timeOffset
        ) {
            writingProgress.estimatedTimeRemaining = remaining
        }
    }

    private func stopObservingWriting() {
        observer?.finish()
        observer = nil
    }
}
