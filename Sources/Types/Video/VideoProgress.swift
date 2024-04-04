//
//  VideoProgress.swift
//
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import AVFoundation

/// Compression Progress
internal class CompressionVideoProgress {
    /// Progress updating queue
    private let queue: DispatchQueue

    /// Base progress variables
    private let progress: Progress
    // Base progress variables
    private let total: Double // steps, min 100
    private let frameDuration: Double // in seconds
    private let timeOffset: Double // Remaining time calculation offset in percentage
    private let duration: Double // in seconds
    private let startTime: Double // in seconds

    /// Writing/saving progress
    private let writingProgress: Progress
    // Writing progress variables
    private let useWritingProgress: Bool
    private var writingInitialized: Bool = false
    private let writingTotal: Int64 // bytes
    private let fileURL: URL
    private var observer: FileSizeObserver?

    /// Time for elapsed and remaining time calculation
    private let startedTime: Date

    /// Public initializer
    public init(
        progress: Progress,
        writingProgress: Progress,
        timeRange: CMTimeRange,
        estimatedFileLengthInKB: Double,
        frameRate: Float?,
        destination: URL,
        queue: DispatchQueue,
        config: FileObserverConfig
    ) {
        self.queue = queue
        startedTime = Date()
        fileURL = destination // writingProgress.fileURL

        startTime = timeRange.start.seconds
        duration = timeRange.duration.seconds
        // Calculate frame duration based on source frame rate
        if let frameRate = frameRate {
            frameDuration = 1.0 / Double(frameRate)
        } else {
            frameDuration = 0.0
        }

        self.progress = progress
        let minSteps: Int64 = 100 // min 100 steps (at least one step per 1%)
        let scaleFactor = 0.5 // 0.5 events per second of source duration
        let total: Int64 = max(Int64(ceil(duration * scaleFactor)), minSteps)
        self.total = Double(total)
        queue.async(qos: .userInteractive) {
            progress.totalUnitCount = total
        }
        self.writingProgress = writingProgress
        writingTotal = Int64(estimatedFileLengthInKB * 1024) // bytes

        // Percentage offset used before starting the remaining time calculations
        switch estimatedFileLengthInKB {
        case 0...10_000: // small file (10MB), 10% offset
            timeOffset = 0.1
        case 10_000...25_000: // medium file (10-25MB), 5% offset
            timeOffset = 0.05
        case 25_000...50_000: // large file (25-50MB), 3% offset
            timeOffset = 0.03
        default: // very big file (>50MB), 1% offset
            timeOffset = 0.01
        }

        // Detect writing progress algorithm
        if estimatedFileLengthInKB < FileObserverConfig.minimalFileLenght {
            // Skip writing progress for small (<25MB) files due to inaccurate file size estimation
            useWritingProgress = false
        } else {
            switch config {
            case .disabled:
                useWritingProgress = false
            case .matching:
                useWritingProgress = true
            // case .directory(let path), .temp(let path): <#FileCreationObserver#>
            }
        }

        // Start file size observer, called once again in encoding progress after time offset is reached
        // Alternatively file creating can be observed before `writer.startWriting()` is called
        if useWritingProgress, FileManager.default.fileExists(atPath: destination.path) { // fileURL.path
            initWriting()
        }
    }

    private func initWriting() {
        guard !writingInitialized else { return }
        writingInitialized = true

        // Determinate progress
        queue.async(qos: .userInteractive) { [self] in
            writingProgress.kind = .file
            writingProgress.totalUnitCount = writingTotal
        }

        #if os(macOS)
        // Publish progress
        writingProgress.publish()
        #endif

        // Run file size changes observer
        let queue = DispatchQueue(label: "FileSizeObserver")
        observer = FileSizeObserver(url: fileURL, queue: queue) { [self] fileSize in
            queue.async(qos: .userInteractive) { [weak self] in
                guard let self = self else { return }
                let fileSize = Int64(fileSize)

                // Actual file size could be larger due to rough file lenght estimation
                guard fileSize < writingProgress.totalUnitCount else {
                    // Update total units, progress will be around 99.99% from this point
                    writingProgress.totalUnitCount = fileSize + 1
                    writingProgress.completedUnitCount = fileSize
                    writingProgress.estimatedTimeRemaining = nil
                    return
                }

                // Filter similar events
                guard fileSize > writingProgress.completedUnitCount + FileObserverConfig.threshold ||
                        writingProgress.completedUnitCount == 0 else {
                    return
                }

                // Update progress
                writingProgress.completedUnitCount = fileSize

                // Calculate estimated remaining time
                if let timeRemaining = writingProgress.estimateRemainingTime(
                    startedAt: startedTime,
                    offset: timeOffset
                ) {
                    writingProgress.estimatedTimeRemaining = timeRemaining
                }
            }
        }
    }

    /// Update encoding progress with new time stamp
    func update(_ timeStamp: CMTime) {
        // Add frame duration to the starting time stamp and
        // distract cutted out media part at the beginning
        let currentTime = timeStamp.seconds + frameDuration - startTime
        // Calculate current progress
        let percentage = currentTime / duration
        guard !percentage.isNaN else { return }

        queue.async(qos: .userInteractive) { [self] in
            // Current step
            var completedUnitCount = Int64(percentage * total) // progress.totalUnitCount

            // Progress can overflow a bit (less than `frameDuration` value)
            completedUnitCount = min(completedUnitCount, progress.totalUnitCount)

            // Check the current state is maximum, due to async processing
            if completedUnitCount > progress.completedUnitCount {
                // Update progress
                progress.completedUnitCount = completedUnitCount

                // Calculate estimated remaining time
                if let timeRemaining = progress.estimateRemainingTime(
                    startedAt: startedTime,
                    offset: timeOffset
                ) {
                    progress.estimatedTimeRemaining = timeRemaining
                }

                // Init writing progress after time offset is reached
                if useWritingProgress, progress.fractionCompleted > timeOffset {
                    initWriting()
                }
            }
        }
    }

    /// Finish encoding progress
    func complete() {
        queue.async(qos: .userInteractive) { [self] in
            // Confirm the progress is 1.0
            if progress.completedUnitCount != progress.totalUnitCount {
                progress.completedUnitCount = progress.totalUnitCount
            }
            // Clear estimated time
            progress.estimatedTimeRemaining = nil
        }
    }

    /// Finish writing/saving progress
    func completeWriting() {
        // Stop observing file size changes
        observer?.finish()

        queue.async(qos: .userInteractive) { [self] in
            if useWritingProgress {
                if writingProgress.totalUnitCount != writingProgress.completedUnitCount {
                    // Set total to actually written bytes amount
                    writingProgress.totalUnitCount = writingProgress.completedUnitCount
                }
                // Clear estimated time
                writingProgress.estimatedTimeRemaining = nil

                #if os(macOS)
                // Unpublish progress
                writingProgress.unpublish()
                #endif
            } else {
                // writingProgress.kind = nil
                writingProgress.completedUnitCount = 1
                writingProgress.totalUnitCount = 1
            }
        }
    }

    /// Cancel writing/saving progress
    func cancelWriting() {
        // Stop observing writing events
        observer?.finish()

        queue.async(qos: .userInteractive) { [self] in
            if useWritingProgress {
                // Clear progress and estimated time
                writingProgress.estimatedTimeRemaining = nil
                writingProgress.totalUnitCount = -1
                writingProgress.completedUnitCount = 0
            }

            #if os(macOS)
            // Unpublish progress
            writingProgress.unpublish()
            #endif
        }
    }
}
