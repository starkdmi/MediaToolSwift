//
//  VideoProgress.swift
//
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import AVFoundation

/// Compression Progress
internal struct CompressionVideoProgress {
    /// Encoding progress
    let encodingProgress: Progress
    // Encoding progress variables
    private let frameDuration: Int64
    private let timeOffset: Double // Remaining time calculation offset in percentage
    private let startTime: CMTimeValue
    private let encodingTotal: CMTimeValue

    /// Writing/saving progress
    let writingProgress: Progress
    // Writing progress variables
    private let useWritingProgress: Bool
    private var writingInitialized: Bool = false
    private let fileURL: URL
    private var observer: FileSizeObserver?

    /// Progress callback
    let onProgress: (_ encoding: Progress, _ writing: Progress?) -> Void
    private let startedTime: Date

    private func updateProgress() {
        onProgress(encodingProgress, useWritingProgress && writingInitialized ? writingProgress : nil)
        // onProgress(encodingProgress, useWritingProgress ? writingProgress : nil)
    }

    /// Public initializer
    public init(
        timeRange: CMTimeRange,
        estimatedFileLengthInKB: Double,
        frameRate: Float?,
        destination: URL,
        config: FileObserverConfig,
        onProgress: @escaping (_ encoding: Progress, _ writing: Progress?) -> Void
    ) {
        self.onProgress = onProgress

        startTime = timeRange.start.value
        let duration = timeRange.duration
        // Calculate frame duration based on source frame rate
        if let frameRate = frameRate {
            frameDuration = Int64(duration.timescale / Int32(frameRate.rounded()))
        } else {
            frameDuration = .zero
        }
        // The progress keeper
        encodingTotal = duration.value
        encodingProgress = Progress(totalUnitCount: encodingTotal)
        startedTime = Date() // elapsed and remaining time calculation
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

        let writingTotal = Int64(estimatedFileLengthInKB * 1024) // bytes
        writingProgress = Progress(totalUnitCount: writingTotal)
        writingProgress.kind = .file
        writingProgress.fileURL = destination
        fileURL = destination
        // Finder progress indicator
        writingProgress.fileOperationKind = .decompressingAfterDownloading // .copying
        writingProgress.isCancellable = false

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
        if useWritingProgress, FileManager.default.fileExists(atPath: destination.path) {
            initWriting()
        }
    }

    mutating private func initWriting() {
        guard !writingInitialized else { return }
        writingInitialized = true

        // Publish progress
        writingProgress.publish()

        // Run file size changes observer
        observer = FileSizeObserver(url: fileURL) { [self] fileSize in
            let fileSize = Int64(fileSize)
            // Actual file size could be larger due to rough file lenght estimation
            if fileSize > writingProgress.totalUnitCount {
                // Update total units, progress will be around 99.99% from this point
                writingProgress.totalUnitCount = fileSize + 1
            }
            // let fileSize = min(Int64(fileSize), writingProgress.totalUnitCount - 1)

            // Filter similar events
            guard writingProgress.completedUnitCount != fileSize else { return }

            // Update progress
            writingProgress.completedUnitCount = fileSize

            // Calculate estimated remaining time
            if let timeRemaining = writingProgress.estimateRemainingTime(
                startedAt: startedTime,
                offset: timeOffset
            ) {
                writingProgress.estimatedTimeRemaining = timeRemaining
            }

            // Notify
            updateProgress()
        }
    }

    /// Update encoding progress with new time stamp
    mutating func updadeEncoding(_ timeStamp: CMTimeValue) {
        // Add frame duration to the starting time stamp
        let currentTime = timeStamp + frameDuration
        // Distract cutted out media part at the beginning
        var completedUnitCount = currentTime - startTime

        // Progress can overflow a bit (less than `frameDuration` value)
        completedUnitCount = min(completedUnitCount, encodingTotal)

        // Check the current state is maximum, due to async processing
        if completedUnitCount > encodingProgress.completedUnitCount {
            encodingProgress.completedUnitCount = completedUnitCount

            // Calculate estimated remaining time
            if let timeRemaining = encodingProgress.estimateRemainingTime(
                startedAt: startedTime,
                offset: timeOffset
            ) {
                encodingProgress.estimatedTimeRemaining = timeRemaining
            }

            // Init writing progress after time offset is reached
            if useWritingProgress, encodingProgress.fractionCompleted > timeOffset {
                initWriting()
            }

            updateProgress()
        }
    }

    /// Finish encoding progress
    func completeEncoding() {
        // Confirm the progress is 1.0
        if encodingProgress.completedUnitCount != encodingTotal {
            encodingProgress.completedUnitCount = encodingTotal
            updateProgress()
        }
    }

    /// Finish writing/saving progress
    func completeWriting() {
        // Stop observing file size changes
        finishWritingObserver(unpublish: false)

        if useWritingProgress, writingProgress.completedUnitCount != writingProgress.totalUnitCount {
            // Set total to actually written bytes amount
            writingProgress.totalUnitCount = writingProgress.completedUnitCount
            // Notify
            updateProgress()
        }

        // Unpublish progress
        writingProgress.unpublish()
    }

    /// Stop observing writing events
    func finishWritingObserver(unpublish: Bool = true) {
        observer?.finish()

        if unpublish {
            writingProgress.unpublish()
        }
    }
}
