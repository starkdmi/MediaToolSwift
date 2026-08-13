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
    private let fileURL: URL
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

        startTime = timeRange.start.seconds
        duration = timeRange.duration.seconds
        if let frameRate, frameRate > 0 {
            frameDuration = 1.0 / Double(frameRate)
        } else {
            frameDuration = 0.0
        }

        let minimumSteps: Int64 = 100
        let scaleFactor = 0.5
        let totalSteps = max(Int64(ceil(duration * scaleFactor)), minimumSteps)
        total = Double(totalSteps)
        self.totalSteps = totalSteps
        writingTotal = Int64(estimatedFileLengthInKB * 1024)

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
            self.configureEncodingProgress()
            if self.useWritingProgress,
               FileManager.default.fileExists(atPath: destination.path) {
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
            self.configureEncodingProgress()
            if self.progress.completedUnitCount != self.progress.totalUnitCount {
                self.progress.completedUnitCount = self.progress.totalUnitCount
            }
            self.progress.estimatedTimeRemaining = nil
        }
    }

    /// Finish writing/saving progress.
    internal func completeWriting() {
        queue.async { [self] in
            self.stopObservingWriting()
            if self.useWritingProgress {
                self.configureWritingProgress()
                if self.writingProgress.totalUnitCount != self.writingProgress.completedUnitCount {
                    self.writingProgress.totalUnitCount = self.writingProgress.completedUnitCount
                }
                self.writingProgress.estimatedTimeRemaining = nil
                #if os(macOS)
                self.writingProgress.unpublish()
                #endif
            } else {
                self.writingProgress.completedUnitCount = 1
                self.writingProgress.totalUnitCount = 1
            }
        }
    }

    /// Clear writing progress after cancellation or failure.
    internal func cancelWriting() {
        queue.async { [self] in
            self.stopObservingWriting()
            if self.useWritingProgress {
                self.configureWritingProgress()
                self.writingProgress.estimatedTimeRemaining = nil
                self.writingProgress.totalUnitCount = -1
                self.writingProgress.completedUnitCount = 0
            }
            #if os(macOS)
            self.writingProgress.unpublish()
            #endif
        }
    }

    private func updateEncoding(percentage: Double) {
        configureEncodingProgress()
        var completedUnitCount = Int64(percentage * total)
        completedUnitCount = min(completedUnitCount, progress.totalUnitCount)

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

    private func configureEncodingProgress() {
        if progress.totalUnitCount != totalSteps {
            progress.totalUnitCount = totalSteps
        }
    }

    private func configureWritingProgress() {
        let writingProgress = self.writingProgress
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
        configureWritingProgress()
        guard !writingInitialized else { return }
        writingInitialized = true

        let observerQueue = DispatchQueue(label: "MediaToolSwift.video.file-size")
        observer = FileSizeObserver(url: fileURL, queue: observerQueue) { [weak self] fileSize in
            self?.queue.async { [weak self] in
                self?.updateWriting(fileSize: Int64(fileSize))
            }
        }
    }

    private func updateWriting(fileSize: Int64) {
        configureWritingProgress()
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
