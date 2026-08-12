import AVFoundation
import XCTest
@testable import MediaToolSwift

private final class TerminalStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let terminalExpectation: XCTestExpectation
    private var states: [CompressionState] = []

    init(_ terminalExpectation: XCTestExpectation) {
        self.terminalExpectation = terminalExpectation
    }

    func record(_ state: CompressionState) {
        guard state != .started else { return }

        lock.lock()
        states.append(state)
        let isFirstTerminalState = states.count == 1
        lock.unlock()

        if isFirstTerminalState {
            terminalExpectation.fulfill()
        }
    }

    func terminalStates() -> [CompressionState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }
}

private final class LifetimeProbe: @unchecked Sendable {
    private let onDeinit: @Sendable () -> Void

    init(onDeinit: @escaping @Sendable () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }
}

private final class SourceEntryReplacer: @unchecked Sendable {
    private let lock = NSLock()
    private let source: URL
    private let backup: URL
    private let replacement: Data
    private var didAttemptReplacement = false
    private var replacementError: Error?

    init(source: URL, backup: URL, replacement: Data) {
        self.source = source
        self.backup = backup
        self.replacement = replacement
    }

    func replace() {
        lock.lock()
        guard !didAttemptReplacement else {
            lock.unlock()
            return
        }
        didAttemptReplacement = true
        lock.unlock()

        do {
            try FileManager.default.moveItem(at: source, to: backup)
            try replacement.write(to: source)
        } catch {
            lock.lock()
            replacementError = error
            lock.unlock()
        }
    }

    func result() -> (didReplace: Bool, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (didAttemptReplacement, replacementError)
    }
}

final class RefactoringVerificationTests: XCTestCase {
    private static let mediaDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("media")

    private var outputDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory
    }

    override func tearDownWithError() throws {
        if let outputDirectory {
            try FileManager.default.removeItem(at: outputDirectory)
        }
        outputDirectory = nil
        try super.tearDownWithError()
    }

    private func fixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let url = Self.mediaDirectory.appendingPathComponent(name)
        return try XCTUnwrap(
            FileManager.default.fileExists(atPath: url.path) ? url : nil,
            "Required fixture is missing: \(name)",
            file: file,
            line: line
        )
    }

    private func outputURL(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        try XCTUnwrap(outputDirectory, "Test output directory was not created", file: file, line: line)
            .appendingPathComponent(name)
    }

    func testVideoPipelineConfigurationMatrix() async throws {
        let source = try fixture("chromecast.mp4")
        let asset = AVAsset(url: source)
        let settings: [CompressionVideoSettings] = [
            .init(codec: .h264),
            .init(codec: .hevc, bitrate: .value(500_000)),
            .init(size: .fit(CGSize(width: 640, height: 360))),
            .init(frameRate: 15),
            .init(edit: [.crop(.init(size: CGSize(width: 640, height: 360)))])
        ]

        for setting in settings {
            let variables = try await VideoTool.initializeVideo(asset: asset, videoSettings: setting)
            XCTAssertNotNil(variables.videoInput)
            XCTAssertNotNil(variables.videoOutput)
            XCTAssertGreaterThan(variables.totalFrames, 0)
        }
    }

    func testSampleBufferToManyRoutesEveryReturnedSample() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("sample-buffer-to-many.mov")
        let processor = VideoFrameProcessor.sampleBufferToMany { sample in
            var sourceTiming = CMSampleTimingInfo()
            guard CMSampleBufferGetSampleTimingInfo(
                sample,
                at: 0,
                timingInfoOut: &sourceTiming
            ) == noErr else {
                return []
            }

            let sourceDuration: CMTime
            if sourceTiming.duration.isValid, sourceTiming.duration.seconds > 0 {
                sourceDuration = sourceTiming.duration
            } else {
                sourceDuration = CMTime(value: 1, timescale: 30)
            }
            let halfDuration = CMTimeMultiplyByRatio(
                sourceDuration,
                multiplier: 1,
                divisor: 2
            )

            func copy(at presentationTime: CMTime) -> CMSampleBuffer? {
                var timing = sourceTiming
                timing.duration = halfDuration
                timing.presentationTimeStamp = presentationTime
                timing.decodeTimeStamp = .invalid
                var copy: CMSampleBuffer?
                let status = CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sample,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleBufferOut: &copy
                )
                return status == noErr ? copy : nil
            }

            return [
                copy(at: sourceTiming.presentationTimeStamp),
                copy(at: CMTimeAdd(sourceTiming.presentationTimeStamp, halfDuration))
            ].compactMap { $0 }
        }
        let settings = CompressionVideoSettings(
            codec: .h264,
            bitrate: .encoder,
            edit: [
                .cut(from: 0, to: 1),
                .process(processor)
            ]
        )

        let configured = try await VideoTool.initializeVideo(
            asset: AVAsset(url: source),
            videoSettings: settings
        )
        XCTAssertNotNil(configured.sampleHandler)
        XCTAssertEqual(processor, processor)
        XCTAssertEqual(processor.hashValue, processor.hashValue)

        let terminal = expectation(description: "multi-sample conversion")
        let recorder = TerminalStateRecorder(terminal)
        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: settings,
            skipAudio: true,
            overwrite: true,
            callback: { recorder.record($0) }
        )

        await fulfillment(of: [terminal], timeout: 30)
        XCTAssertEqual(recorder.terminalStates().count, 1)
        guard case .completed = recorder.terminalStates().first else {
            return XCTFail("Expected multi-sample conversion to complete")
        }

        let outputAsset = AVAsset(url: destination)
        let loadedOutputTrack = await outputAsset.getFirstTrack(withMediaType: .video)
        let outputTrack = try XCTUnwrap(loadedOutputTrack)
        let reader = try AVAssetReader(asset: outputAsset)
        let output = AVAssetReaderTrackOutput(track: outputTrack, outputSettings: nil)
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var outputSamples = 0
        while output.copyNextSampleBuffer() != nil {
            outputSamples += 1
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertGreaterThan(outputSamples, Int(configured.totalFrames))
    }

    func testVideoTerminalCallbackWaitsForInFlightProcessor() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("processor-cancellation-order.mov")
        let processorEntered = expectation(description: "processor entered")
        let terminal = expectation(description: "terminal callback")
        let releaseProcessor = DispatchSemaphore(value: 0)
        defer { releaseProcessor.signal() }
        let recorder = TerminalStateRecorder(terminal)
        let processor = VideoFrameProcessor.sampleBuffer { sample in
            processorEntered.fulfill()
            releaseProcessor.wait()
            return sample
        }
        let settings = CompressionVideoSettings(
            codec: .h264,
            edit: [
                .cut(from: 0, to: 1),
                .process(processor)
            ]
        )

        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: settings,
            skipAudio: true,
            overwrite: true,
            callback: { recorder.record($0) }
        )

        await fulfillment(of: [processorEntered], timeout: 10)
        task.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(
            recorder.terminalStates().isEmpty,
            "Terminal delivery must not overlap an in-flight public processor"
        )

        releaseProcessor.signal()
        await fulfillment(of: [terminal], timeout: 10)
        XCTAssertEqual(recorder.terminalStates(), [.cancelled])
    }

    func testInvalidAndShortFrameRatesDoNotTrap() async throws {
        let videoSource = try fixture("chromecast.mp4")
        let asset = AVAsset(url: videoSource)

        for frameRate in [0, -1] {
            do {
                _ = try await VideoTool.initializeVideo(
                    asset: asset,
                    videoSettings: .init(frameRate: frameRate)
                )
                XCTFail("Expected invalid frame rate \(frameRate) to fail")
            } catch let error as CompressionError {
                XCTAssertEqual(error, .invalidFrameRate)
            }
        }

        let animation = try fixture("amazing.gif")
        for frameRate in [0, -1] {
            XCTAssertThrowsError(
                try ImageTool.decode(source: animation, settings: .init(frameRate: frameRate))
            ) { error in
                XCTAssertEqual(error as? CompressionError, .invalidFrameRate)
            }
        }

        let oneFrame = try ImageTool.decode(
            source: animation,
            settings: .init(frameRate: 1)
        )
        XCTAssertEqual(oneFrame.frames.count, 1)
    }

    func testAudioPipelineConfigurationMatrix() async throws {
        let source = try fixture("oludeniz.MOV")
        let asset = AVAsset(url: source)
        let settings: [CompressionAudioSettings?] = [
            nil,
            .init(codec: .aac, bitrate: .value(96_000)),
            .init(codec: .flac),
            .init(codec: .alac)
        ]

        for setting in settings {
            let variables = try await VideoTool.initializeAudio(asset: asset, audioSettings: setting)
            XCTAssertFalse(variables.skipAudio)
            XCTAssertNotNil(variables.audioTrack)
            XCTAssertNotNil(variables.audioInput)
            XCTAssertNotNil(variables.audioOutput)
        }
    }

    func testMetadataPipelinePreservesAndOverridesMetadata() async throws {
        let source = try fixture("oludeniz.MOV")
        let asset = AVAsset(url: source)
        let custom = AVMutableMetadataItem()
        custom.keySpace = .common
        custom.key = AVMetadataKey.commonKeyTitle as NSString
        custom.value = "MediaToolSwift" as NSString

        let preserved = await VideoTool.initializeMetadata(
            asset: asset,
            skipSourceMetadata: false,
            customMetadata: [custom]
        )
        let stripped = await VideoTool.initializeMetadata(
            asset: asset,
            skipSourceMetadata: true,
            customMetadata: [custom]
        )

        XCTAssertGreaterThan(preserved.metadata.count, stripped.metadata.count)
        XCTAssertEqual(stripped.metadata.count, 1)
    }

    func testImagePipelineUsesCheckedInJPEGAnimationAndHDRFixtures() throws {
        let jpeg = try fixture("iphone_x.jpg")
        let animation = try fixture("amazing.gif")
        let hdr = try fixture("oludeniz.heic")
        let destination = try outputURL("stabilization.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let converted = try ImageTool.convert(
            source: jpeg,
            destination: destination,
            settings: .init(format: .jpeg, size: .fit(.hd))
        )
        let animatedImage = try ImageTool.decode(source: animation)
        let hdrImage = try ImageTool.decode(source: hdr)

        // `ImageInfo.size` is the encoded pixel size; ImageTest separately
        // verifies the portrait display size after applying EXIF orientation.
        XCTAssertEqual(converted.size, CGSize(width: 1280, height: 960))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertGreaterThan(animatedImage.frames.count, 1)
        XCTAssertTrue(hdrImage.info.isHDR)
    }

    func testImagePublicBoundariesRejectInvalidFormatsAndIndexes() throws {
        let source = try fixture("starkdev.png")
        let image = try ImageTool.decode(source: source)
        let customDestination = try outputURL("missing.custom")

        XCTAssertThrowsError(
            try ImageTool.encode(
                image.frames,
                at: customDestination,
                settings: .init(format: .custom("missing"))
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .unsupportedImageFormat)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: customDestination.path))

        let indexDestination = try outputURL("invalid-index.png")
        XCTAssertThrowsError(
            try ImageTool.encode(
                image.frames,
                at: indexDestination,
                settings: .init(format: .png),
                primaryIndex: image.frames.count
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .invalidImagePrimaryIndex)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexDestination.path))

        let edited = ImageTool.edit(
            image.frames,
            settings: .init(),
            processingMethod: image.processingMethod,
            hasAlpha: image.hasAlpha,
            primaryIndex: image.frames.count
        )
        XCTAssertEqual(edited.frames.count, image.frames.count)
        XCTAssertEqual(edited.size, .zero)
    }

    func testImageOverwriteIsTransactional() throws {
        let fixture = try fixture("starkdev.png")
        let inPlaceSource = try outputURL("in-place.png")
        try FileManager.default.copyItem(at: fixture, to: inPlaceSource)
        let originalData = try Data(contentsOf: inPlaceSource)

        XCTAssertThrowsError(
            try ImageTool.convert(
                source: inPlaceSource,
                destination: inPlaceSource,
                settings: .init(format: .png),
                overwrite: true
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .cannotOverWrite)
        }
        XCTAssertEqual(try Data(contentsOf: inPlaceSource), originalData)

        let corruptSource = try outputURL("corrupt.png")
        let destination = try outputURL("existing.png")
        let corruptData = Data("not an image".utf8)
        let sentinelData = Data("existing destination".utf8)
        try corruptData.write(to: corruptSource)
        try sentinelData.write(to: destination)

        XCTAssertThrowsError(
            try ImageTool.convert(
                source: corruptSource,
                destination: destination,
                settings: .init(format: .png),
                overwrite: true
            )
        )
        XCTAssertEqual(try Data(contentsOf: destination), sentinelData)

        _ = try ImageTool.convert(
            source: fixture,
            destination: destination,
            settings: .init(format: .png),
            overwrite: true
        )
        XCTAssertNotEqual(try Data(contentsOf: destination), sentinelData)
        XCTAssertNotNil(CGImageSourceCreateWithURL(destination as CFURL, nil))
    }

    func testOutputTransactionsReserveOneWriterPerDestination() throws {
        let destination = try outputURL("reserved-output.bin")
        let firstPayload = Data("first payload".utf8)
        let secondPayload = Data("second payload".utf8)
        var first: FileOutputTransaction? = try FileOutputTransaction(
            destination: destination,
            overwrite: true
        )

        XCTAssertThrowsError(
            try FileOutputTransaction(destination: destination, overwrite: true)
        ) { error in
            guard let compressionError = error as? CompressionError,
                  case .destinationFileExists = compressionError else {
                return XCTFail("Unexpected reservation error: \(error)")
            }
        }

        try firstPayload.write(to: try XCTUnwrap(first).outputURL)
        try first?.commit()
        XCTAssertEqual(try Data(contentsOf: destination), firstPayload)

        // A completed transaction must stop reserving the destination even
        // while a terminal callback's stack still retains the transaction.
        let second = try FileOutputTransaction(destination: destination, overwrite: true)
        first = nil
        try secondPayload.write(to: second.outputURL)
        try second.commit()
        XCTAssertEqual(try Data(contentsOf: destination), secondPayload)
    }

    func testOutputTransactionRejectsDirectoriesAndPreservesConcurrentReplacement() throws {
        let destinationDirectory = try outputURL("directory-destination.mov")
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: false)
        let sentinel = destinationDirectory.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)

        XCTAssertThrowsError(
            try FileOutputTransaction(destination: destinationDirectory, overwrite: true)
        ) { error in
            XCTAssertEqual(error as? CompressionError, .cannotOverWrite)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))

        let destination = try outputURL("transaction-replacement.mov")
        try Data("original".utf8).write(to: destination)
        let transaction = try FileOutputTransaction(destination: destination, overwrite: true)
        try Data("encoded".utf8).write(to: transaction.outputURL)
        transaction.captureOutputIdentityIfPresent()
        try Data("replacement".utf8).write(to: destination, options: .atomic)

        XCTAssertThrowsError(try transaction.commit())
        transaction.discard()
        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.outputURL.path))
    }

    func testFilesystemAliasesCannotBypassSafetyChecks() throws {
        let fixture = try fixture("starkdev.png")
        let source = try outputURL("alias-source.png")
        let sourceAlias = try outputURL("alias-destination.png")
        try FileManager.default.copyItem(at: fixture, to: source)
        try FileManager.default.createSymbolicLink(at: sourceAlias, withDestinationURL: source)
        let originalData = try Data(contentsOf: source)

        XCTAssertThrowsError(
            try ImageTool.convert(
                source: source,
                destination: sourceAlias,
                settings: .init(format: .png),
                overwrite: true,
                deleteSourceFile: true
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .cannotOverWrite)
        }
        XCTAssertEqual(try Data(contentsOf: source), originalData)

        let realDirectory = try outputURL("real-directory")
        let aliasDirectory = try outputURL("directory-alias")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory,
            withDestinationURL: realDirectory
        )

        let first = try FileOutputTransaction(
            destination: realDirectory.appendingPathComponent("shared.bin"),
            overwrite: true
        )
        try withExtendedLifetime(first) {
            XCTAssertThrowsError(
                try FileOutputTransaction(
                    destination: aliasDirectory.appendingPathComponent("shared.bin"),
                    overwrite: true
                )
            ) { error in
                XCTAssertEqual(error as? CompressionError, .destinationFileExists)
            }
        }
    }

    func testVideoBitrateRejectsNonFiniteValuesAndPreservesCappingParity() throws {
        let calculator = VideoBitrateCalculator()
        let sourceSize = CGSize(width: 1920, height: 1080)

        for invalidSize in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertThrowsError(
                try calculator.calculate(
                    bitrateOption: .filesize(invalidSize),
                    sourceBitrate: 1_000_000,
                    targetSize: sourceSize,
                    sourceSize: sourceSize,
                    codec: .h264,
                    codecChanged: false,
                    isHDR: false,
                    frameRate: 30,
                    duration: 10
                )
            ) { error in
                XCTAssertEqual(error as? CompressionError, .invalidVideoBitrate)
            }
        }

        let capped = try calculator.calculate(
            bitrateOption: .value(8_000_000),
            sourceBitrate: 1_000_000,
            targetSize: CGSize(width: 1280, height: 720),
            sourceSize: sourceSize,
            codec: .h264,
            codecChanged: false,
            isHDR: false,
            frameRate: 30,
            duration: 10
        )
        XCTAssertNil(capped.targetBitrate)
        XCTAssertEqual(capped.encoderBitrate, 1_000_000)
    }

    func testExtendedLocationParsingRejectsMalformedDataAndSupportsUnalignedPayloads() throws {
        for byteCount in [0, 1, 7, 8, 15, 16, 31, 63] {
            let info = FileExtendedAttributes.extractExtendedFileInfo(from: [
                FileExtendedAttributes.customLocationKey: Data(repeating: 0, count: byteCount)
            ])
            XCTAssertNil(info.location, "Accepted a truncated \(byteCount)-byte location payload")
        }

        var payload = Data(repeating: 0, count: 64)
        func store(_ value: Double, at offset: Int) {
            var value = value
            Swift.withUnsafeBytes(of: &value) { bytes in
                payload.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
            }
        }
        store(36.5482, at: 0)
        store(29.1116, at: 8)
        store(4.766546, at: 24)
        store(688_827_791, at: 56)

        // Slicing after a one-byte prefix can expose a non-natively-aligned base
        // address. Decoding must not depend on the payload's alignment.
        var prefixedPayload = Data([0])
        prefixedPayload.append(payload)
        let unalignedPayload: Data = prefixedPayload.dropFirst()
        let info = FileExtendedAttributes.extractExtendedFileInfo(from: [
            FileExtendedAttributes.customLocationKey: unalignedPayload
        ])
        let location = try XCTUnwrap(info.location)
        XCTAssertEqual(location.coordinate.latitude, 36.5482, accuracy: 0.000_001)
        XCTAssertEqual(location.coordinate.longitude, 29.1116, accuracy: 0.000_001)
        XCTAssertEqual(location.horizontalAccuracy, 4.766546, accuracy: 0.000_001)

        store(Double.nan, at: 0)
        let invalid = FileExtendedAttributes.extractExtendedFileInfo(from: [
            FileExtendedAttributes.customLocationKey: payload
        ])
        XCTAssertNil(invalid.location)
    }

    func testVideoProgressClampsFiniteOutOfRangeTimestamps() async throws {
        let destination = try outputURL("bounded-progress.mov")
        let task = CompressionTask(destination: destination)
        let progress = CompressionVideoProgress(
            task: task,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 1, preferredTimescale: 600)
            ),
            estimatedFileLengthInKB: 0,
            frameRate: nil,
            destination: destination,
            observedOutput: destination,
            queue: DispatchQueue(label: "MediaToolSwiftTests.bounded-progress"),
            config: .disabled
        )

        progress.update(CMTime(value: Int64.min + 1, timescale: 1))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(task.progress.completedUnitCount, 0)

        // This timestamp yields a huge but finite percentage. Converting it to
        // Int64 before bounding used to trap.
        progress.update(CMTime(value: Int64.max, timescale: 1))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(task.progress.completedUnitCount, task.progress.totalUnitCount)
    }

    func testAnimatedFrameRateAdjustmentRetainsAndRemapsPrimaryFrame() throws {
        var frames = (0 ..< 5).map { index -> ImageFrame in
            var frame = ImageFrame()
            frame.unclampedDelayTime = 0.1
            frame.canvasWidth = Double(index)
            return frame
        }
        frames[0].loopCount = 7

        let adjusted = try frames.withAdjustedFrameRate(
            frameRate: 2,
            duration: 0.5,
            primaryIndex: 3
        )

        XCTAssertEqual(adjusted.frames?.count, 1)
        XCTAssertEqual(adjusted.primaryIndex, 0)
        XCTAssertEqual(adjusted.frames?.first?.canvasWidth, 3)
        XCTAssertEqual(adjusted.frames?.first?.loopCount, 7)
    }

    func testAnimatedFrameRateAdjustmentPreservesVariableTimelineAcrossPrimaryRotation() throws {
        let delays = [0.05, 0.10, 0.15, 0.20, 0.25, 0.25]
        var frames = delays.enumerated().map { index, delay -> ImageFrame in
            var frame = ImageFrame()
            frame.unclampedDelayTime = delay
            frame.canvasWidth = Double(index)
            return frame
        }
        frames[0].loopCount = 7

        let adjusted = try frames.withAdjustedFrameRate(
            frameRate: 3,
            duration: 1,
            primaryIndex: 3
        )
        let adjustedFrames = try XCTUnwrap(adjusted.frames)

        // Source-order retention remains cyclically ordered. HEICS encoding
        // rotates this sequence to [3, 5, 0] so the primary is emitted first.
        XCTAssertEqual(adjustedFrames.compactMap(\.canvasWidth), [0, 3, 5])
        XCTAssertEqual(adjustedFrames.compactMap(\.loopCount), [7])
        XCTAssertEqual(adjusted.primaryIndex, 1)

        let adjustedDelays = adjustedFrames.map {
            $0.unclampedDelayTime ?? $0.delayTime ?? 0
        }
        XCTAssertEqual(adjustedDelays[0], 0.30, accuracy: 0.000_001)
        XCTAssertEqual(adjustedDelays[1], 0.45, accuracy: 0.000_001)
        XCTAssertEqual(adjustedDelays[2], 0.25, accuracy: 0.000_001)
        XCTAssertEqual(adjustedDelays.reduce(0, +), 1, accuracy: 0.000_001)
    }

    func testThumbnailCollectorPreservesRequestIndexesAcrossFailuresAndReordering() throws {
        let source = try fixture("starkdev.png")
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let requestedTimes = [1.0, 2.0, 3.0].map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }
        let completed = expectation(description: "thumbnail collection")
        let result = LockedValue<[VideoThumbnail]>([])
        let collector = VideoThumbnailCollector(requestedTimes: requestedTimes) { thumbnails in
            result.set(thumbnails)
            completed.fulfill()
        }

        collector.receive(image: image, requestedTime: requestedTimes[2], actualTime: 3)
        collector.receive(image: nil, requestedTime: requestedTimes[1], actualTime: 2)
        collector.receive(image: image, requestedTime: requestedTimes[0], actualTime: 1)

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(result.read().map(\.requestIndex), [0, 2])
        XCTAssertEqual(result.read().map(\.requestedTime), [1, 3])
    }

    func testAudioConversionHonorsDeleteSourceAndCacheDirectory() async throws {
        let fixture = try fixture("440Hz.mp3")
        let source = try outputURL("source.mp3")
        let destination = try outputURL("output.m4a")
        let cache = FileManager.default.temporaryDirectory
        let sentinelData = Data("existing audio output".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)
        try sentinelData.write(to: destination)

        let completed = expectation(description: "conversion completed")
        let terminalState = LockedValue<CompressionState?>(nil)
        _ = await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            cacheDirectory: cache,
            overwrite: true,
            deleteSourceFile: true
        ) { state in
            switch state {
            case .completed:
                terminalState.set(state)
                completed.fulfill()
            case .failed(let error):
                XCTFail("Audio conversion failed: \(error)")
                terminalState.set(state)
                completed.fulfill()
            case .cancelled:
                XCTFail("Audio conversion was cancelled unexpectedly")
                terminalState.set(state)
                completed.fulfill()
            case .started:
                break
            }
        }

        await fulfillment(of: [completed], timeout: 30)
        guard case .completed = terminalState.read() else {
            return XCTFail("Expected successful conversion, got \(String(describing: terminalState.read()))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNotEqual(try Data(contentsOf: destination), sentinelData)
        let audioTrack = await AVAsset(url: destination).getFirstTrack(withMediaType: .audio)
        XCTAssertNotNil(audioTrack)
    }

    func testImageDeleteSourcePreservesAReplacementEntry() throws {
        let fixture = try fixture("starkdev.png")
        let source = try outputURL("replace-image-source.png")
        let backup = try outputURL("replace-image-original.png")
        let destination = try outputURL("replace-image-output.jpg")
        let replacement = Data("replacement image entry".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)

        let replacer = SourceEntryReplacer(
            source: source,
            backup: backup,
            replacement: replacement
        )
        let processor: ImageProcessor = { ciImage, cgImage, _, _ in
            replacer.replace()
            return (ciImage, cgImage)
        }

        _ = try ImageTool.convert(
            source: source,
            destination: destination,
            settings: .init(
                format: .jpeg,
                edit: [.imageProcessing(processor)],
                preferredFramework: .cgImage
            ),
            overwrite: true,
            deleteSourceFile: true
        )

        let replacementResult = replacer.result()
        XCTAssertTrue(replacementResult.didReplace)
        XCTAssertNil(replacementResult.error)
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAudioDeleteSourcePreservesAReplacementEntry() async throws {
        let fixture = try fixture("440Hz.mp3")
        let source = try outputURL("replace-audio-source.mp3")
        let backup = try outputURL("replace-audio-original.mp3")
        let destination = try outputURL("replace-audio-output.m4a")
        let replacement = Data("replacement audio entry".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)

        let replacer = SourceEntryReplacer(
            source: source,
            backup: backup,
            replacement: replacement
        )
        let terminal = expectation(description: "audio source replacement")
        let recorder = TerminalStateRecorder(terminal)
        _ = await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            overwrite: true,
            deleteSourceFile: true
        ) { state in
            if state == .started {
                replacer.replace()
            } else {
                recorder.record(state)
            }
        }

        await fulfillment(of: [terminal], timeout: 30)
        guard case .completed = recorder.terminalStates().first else {
            return XCTFail("Expected audio conversion to complete after replacing its source entry")
        }
        let replacementResult = replacer.result()
        XCTAssertTrue(replacementResult.didReplace)
        XCTAssertNil(replacementResult.error)
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testVideoDeleteSourcePreservesAReplacementEntry() async throws {
        let fixture = try fixture("chromecast.mp4")
        let source = try outputURL("replace-video-source.mp4")
        let backup = try outputURL("replace-video-original.mp4")
        let destination = try outputURL("replace-video-output.mov")
        let replacement = Data("replacement video entry".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)

        let replacer = SourceEntryReplacer(
            source: source,
            backup: backup,
            replacement: replacement
        )
        let terminal = expectation(description: "video source replacement")
        let recorder = TerminalStateRecorder(terminal)
        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(
                codec: .h264,
                bitrate: .encoder,
                edit: [.cut(from: 0, to: 1)]
            ),
            skipAudio: true,
            overwrite: true,
            deleteSourceFile: true
        ) { state in
            if state == .started {
                replacer.replace()
            } else {
                recorder.record(state)
            }
        }

        await fulfillment(of: [terminal], timeout: 30)
        guard case .completed = recorder.terminalStates().first else {
            return XCTFail("Expected video conversion to complete after replacing its source entry")
        }
        let replacementResult = replacer.result()
        XCTAssertTrue(replacementResult.didReplace)
        XCTAssertNil(replacementResult.error)
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testVideoOverwritePublishesOnlyCompletedOutput() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("transactional-video.mov")
        let sentinelData = Data("existing video output".utf8)
        try sentinelData.write(to: destination)

        let terminal = expectation(description: "transactional video replacement")
        let recorder = TerminalStateRecorder(terminal)
        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(
                codec: .h264,
                bitrate: .encoder,
                edit: [.cut(from: 0, to: 1)]
            ),
            skipAudio: true,
            overwrite: true,
            callback: { recorder.record($0) }
        )

        await fulfillment(of: [terminal], timeout: 30)
        guard case .completed = recorder.terminalStates().first else {
            return XCTFail("Expected video replacement to complete")
        }
        XCTAssertNotEqual(try Data(contentsOf: destination), sentinelData)
        let videoTrack = await AVAsset(url: destination).getFirstTrack(withMediaType: .video)
        XCTAssertNotNil(videoTrack)
    }

    func testAudioProgressQueueDoesNotRetainCompletedSession() async throws {
        let source = try fixture("440Hz.mp3")
        let destination = try outputURL("progress-retention.m4a")
        let terminal = expectation(description: "audio conversion terminal")
        let released = expectation(description: "callback lifetime released")
        let inactiveQueue = DispatchQueue(
            label: "MediaToolSwiftTests.inactive-progress",
            attributes: .initiallyInactive
        )
        defer { inactiveQueue.activate() }
        weak var weakProbe: LifetimeProbe?

        do {
            let probe = LifetimeProbe {
                released.fulfill()
            }
            weakProbe = probe

            _ = await AudioTool.convert(
                source: source,
                destination: destination,
                settings: .init(codec: .aac, bitrate: .value(96_000)),
                overwrite: true,
                progressQueue: inactiveQueue
            ) { [probe] state in
                _ = probe
                if state != .started {
                    terminal.fulfill()
                }
            }

            await fulfillment(of: [terminal], timeout: 30)
        }

        await fulfillment(of: [released], timeout: 5)
        XCTAssertNil(weakProbe)
    }

    func testTaskSynchronizesReplacementProgressCancellation() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-progress-\(UUID().uuidString).mov")

        let task = CompressionTask(destination: destination)
        let replacement = Progress(totalUnitCount: 100)
        task.progress = replacement
        replacement.cancel()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(task.isCancelled)

        let cancelledTask = CompressionTask(destination: destination)
        cancelledTask.cancel()
        let replacementProgress = Progress(totalUnitCount: 100)
        let replacementWritingProgress = Progress(totalUnitCount: 100)
        cancelledTask.progress = replacementProgress
        cancelledTask.writingProgress = replacementWritingProgress

        XCTAssertTrue(replacementProgress.isCancelled)
        XCTAssertTrue(replacementWritingProgress.isCancelled)

        let activeTask = CompressionTask(destination: destination)
        let staleProgress = activeTask.progress
        let activeProgress = Progress(totalUnitCount: 100)
        activeTask.progress = activeProgress
        staleProgress.cancel()

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(activeTask.isCancelled)

        activeProgress.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(activeTask.isCancelled)

        let propagationTask = CompressionTask(destination: destination)
        let propagated = expectation(description: "internal cancellation propagated")
        let progressHandlerEntered = expectation(description: "public progress handler entered")
        let releaseProgressHandler = DispatchSemaphore(value: 0)
        propagationTask.registerCancellationHandler {
            propagated.fulfill()
        }
        propagationTask.progress.cancellationHandler = {
            progressHandlerEntered.fulfill()
            releaseProgressHandler.wait()
        }
        DispatchQueue.global().async {
            propagationTask.cancel()
        }

        await fulfillment(of: [propagated, progressHandlerEntered], timeout: 1)
        releaseProgressHandler.signal()

        let cancellationWins = CompressionTask(destination: destination)
        cancellationWins.cancel()
        switch cancellationWins.claimFailureTerminalOutcome() {
        case .cancellation:
            break
        case .failure, .unavailable:
            XCTFail("A failure must not win after cancellation changed task state")
        }
    }

    func testConcurrentProgressReplacementKeepsWinningCancellationHandler() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-progress-race-\(UUID().uuidString).mov")
        let cancellationPropagated = expectation(description: "all winning progress handlers propagated")
        cancellationPropagated.expectedFulfillmentCount = 50
        var tasks: [CompressionTask] = []

        // Reuse the same pair to exercise A -> B -> A publication. A setter
        // that clears its previous progress after releasing the task lock can
        // otherwise erase a newer setter's handler on the winning instance.
        for _ in 0 ..< cancellationPropagated.expectedFulfillmentCount {
            let task = CompressionTask(destination: destination)
            let progressA = Progress(totalUnitCount: 100)
            let progressB = Progress(totalUnitCount: 100)
            task.registerCancellationHandler {
                cancellationPropagated.fulfill()
            }

            DispatchQueue.concurrentPerform(iterations: 128) { index in
                task.progress = index.isMultiple(of: 2) ? progressA : progressB
            }

            task.progress.cancel()
            tasks.append(task)
        }

        wait(for: [cancellationPropagated], timeout: 5)
        XCTAssertTrue(tasks.allSatisfy(\.isCancelled))
    }

    func testRepeatedAudioCancellationHasOneTerminalEventAndPreservesSource() async throws {
        let fixture = try fixture("chromecast.mp4")
        let source = try outputURL("cancellable-source.mov")
        let destination = try outputURL("cancellable-output.m4a")
        let sentinelData = Data("existing audio destination".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)
        try sentinelData.write(to: destination)

        let terminal = expectation(description: "audio cancellation terminal event")
        let recorder = TerminalStateRecorder(terminal)
        let task = await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            overwrite: true,
            deleteSourceFile: true,
            callback: { recorder.record($0) }
        )

        task.progress.cancel()
        task.cancel()
        task.cancel()
        task.writingProgress.cancel()

        await fulfillment(of: [terminal], timeout: 20)
        try await Task.sleep(nanoseconds: 100_000_000)

        let states = recorder.terminalStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), sentinelData)
    }

    func testRepeatedVideoCancellationHasOneTerminalEventAndPreservesSource() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let source = try outputURL("cancellable-video-source.mov")
        let destination = try outputURL("cancellable-video-output.mov")
        let sentinelData = Data("existing video destination".utf8)
        try FileManager.default.copyItem(at: fixture, to: source)
        try sentinelData.write(to: destination)

        let terminal = expectation(description: "video cancellation terminal event")
        let recorder = TerminalStateRecorder(terminal)
        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(codec: .hevc, bitrate: .encoder),
            skipAudio: true,
            overwrite: true,
            deleteSourceFile: true,
            callback: { recorder.record($0) }
        )

        task.progress.cancel()
        task.cancel()
        task.cancel()
        task.writingProgress.cancel()

        await fulfillment(of: [terminal], timeout: 20)
        try await Task.sleep(nanoseconds: 100_000_000)

        let states = recorder.terminalStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), sentinelData)
    }

    func testVideoStartedCallbackCannotBlockTaskReturn() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let source = try outputURL("blocking-started-source.mov")
        let destination = try outputURL("blocking-started-output.mov")
        try FileManager.default.copyItem(at: fixture, to: source)

        let started = expectation(description: "started callback entered")
        let returned = expectation(description: "conversion call returned its task")
        let terminal = expectation(description: "conversion cancelled")
        let releaseStarted = DispatchSemaphore(value: 0)
        let returnedTask = LockedValue<CompressionTask?>(nil)
        let terminalState = LockedValue<CompressionState?>(nil)

        Task { @Sendable in
            let task = await VideoTool.convert(
                source: source,
                destination: destination,
                videoSettings: .init(codec: .hevc, bitrate: .encoder),
                skipAudio: true,
                overwrite: true
            ) { state in
                switch state {
                case .started:
                    started.fulfill()
                    releaseStarted.wait()
                case .completed, .cancelled, .failed:
                    terminalState.set(state)
                    terminal.fulfill()
                }
            }
            returnedTask.set(task)
            returned.fulfill()
        }

        // `.started` may run before the async API returns, but it must not run
        // in a synchronous handoff that prevents the caller receiving its task.
        await fulfillment(of: [started, returned], timeout: 10)
        guard let task = returnedTask.read() else {
            releaseStarted.signal()
            return XCTFail("The conversion did not return its task")
        }
        task.cancel()
        releaseStarted.signal()

        await fulfillment(of: [terminal], timeout: 10)
        XCTAssertEqual(terminalState.read(), .cancelled)
    }

    func testConcurrentCancellationStressPreservesEverySource() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let cancellationQueue = DispatchQueue(
            label: "MediaToolSwiftTests.concurrent-cancellation",
            attributes: .concurrent
        )
        var recorders: [TerminalStateRecorder] = []
        var sources: [URL] = []
        var destinations: [URL] = []
        var expectations: [XCTestExpectation] = []

        for index in 0 ..< 2 {
            let source = try outputURL("concurrent-audio-\(index).mov")
            let destination = try outputURL("concurrent-audio-\(index).m4a")
            try FileManager.default.copyItem(at: fixture, to: source)
            let terminal = expectation(description: "concurrent audio \(index)")
            let recorder = TerminalStateRecorder(terminal)
            let task = await AudioTool.convert(
                source: source,
                destination: destination,
                settings: .init(codec: .aac, bitrate: .value(96_000)),
                overwrite: true,
                deleteSourceFile: true,
                callback: { recorder.record($0) }
            )
            cancellationQueue.async {
                task.progress.cancel()
                task.cancel()
                task.cancel()
                task.writingProgress.cancel()
            }
            recorders.append(recorder)
            sources.append(source)
            destinations.append(destination)
            expectations.append(terminal)
        }

        for index in 0 ..< 2 {
            let source = try outputURL("concurrent-video-source-\(index).mov")
            let destination = try outputURL("concurrent-video-output-\(index).mov")
            try FileManager.default.copyItem(at: fixture, to: source)
            let terminal = expectation(description: "concurrent video \(index)")
            let recorder = TerminalStateRecorder(terminal)
            let task = await VideoTool.convert(
                source: source,
                destination: destination,
                videoSettings: .init(codec: .hevc, bitrate: .encoder),
                skipAudio: true,
                overwrite: true,
                deleteSourceFile: true,
                callback: { recorder.record($0) }
            )
            cancellationQueue.async {
                task.progress.cancel()
                task.cancel()
                task.cancel()
                task.writingProgress.cancel()
            }
            recorders.append(recorder)
            sources.append(source)
            destinations.append(destination)
            expectations.append(terminal)
        }

        await fulfillment(of: expectations, timeout: 30)
        try await Task.sleep(nanoseconds: 100_000_000)

        for index in recorders.indices {
            let states = recorders[index].terminalStates()
            XCTAssertEqual(states.count, 1, "session \(index) emitted multiple terminal states")
            XCTAssertEqual(states.first, .cancelled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sources[index].path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destinations[index].path))
        }
    }
}
