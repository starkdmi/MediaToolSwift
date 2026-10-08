import AVFoundation
import XCTest
@testable import MediaToolSwift

/// Captures the outcome of a conversion running in a child task.
///
/// The 2.0 API reports its terminal state by resuming the caller, so a test that
/// needs to assert "no terminal state yet" observes this probe instead of a
/// callback recorder.
private final class ConversionProbe<Info: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Info, any Error>?

    func store(_ result: Result<Info, any Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    var hasFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    var isCancellation: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .failure(let error) = result else { return false }
        return error is CancellationError
    }
}

/// Waits until a conversion leaves preparation.
///
/// `.started` is no longer observable through the public API, but the pipeline
/// publishes a real unit count on `task.progress` immediately before the sample
/// pumps run, so polling for it puts a subsequent cancellation in the reading
/// phase rather than in preparation. Returns `false` on timeout.
private func waitForConversionStart(
    _ task: CompressionTask,
    timeout: TimeInterval = 30
) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while task.progress.totalUnitCount <= 0 {
        guard Date() < deadline else { return false }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    return true
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

        _ = try await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: settings,
            skipAudio: true,
            overwrite: true
        )

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

    /// `AVAssetWriterInputPixelBufferAdaptor.pixelBufferPool` hands out
    /// VideoToolbox's current pool without retaining it, and VideoToolbox
    /// replaces that pool a few frames into encoding, sometimes on its own
    /// encoder thread. Reading the property while that replacement releases
    /// the old pool can retain a pool that is already being finalized, and
    /// `CVPixelBufferPoolCreatePixelBuffer` then crashes on its cleared
    /// backing. The pipeline therefore owns the pool it gives frame
    /// processors, so one pool must serve the entire conversion.
    func testPixelBufferProcessorReceivesOnePoolForTheWholeConversion() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("stable-pixel-buffer-pool.mov")
        // Strong references keep each pool alive, so identity comparisons
        // cannot be confused by a later pool reusing a freed address.
        let pools = LockedValue<[CVPixelBufferPool]>([])
        let processor = VideoFrameProcessor.pixelBuffer { buffer, pool, _, _ in
            pools.withValue { $0.append(pool) }
            var output: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess else {
                return nil
            }
            return output
        }
        let settings = CompressionVideoSettings(
            codec: .h264,
            edit: [
                .cut(from: 0, to: 1),
                .process(processor)
            ]
        )

        _ = try await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: settings,
            skipAudio: true,
            overwrite: true
        )

        let received = pools.read()
        // VideoToolbox swaps its pool within the first few frames, so the
        // check only means something when the clip outlasts that point.
        XCTAssertGreaterThan(received.count, 10)
        let first = try XCTUnwrap(received.first)
        XCTAssertTrue(
            received.allSatisfy { $0 === first },
            "Frame processors received \(Set(received.map(ObjectIdentifier.init)).count) different pools"
        )
    }

    func testVideoTerminalResultWaitsForInFlightProcessor() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("processor-cancellation-order.mov")
        let processorEntered = expectation(description: "processor entered")
        let releaseProcessor = DispatchSemaphore(value: 0)
        defer { releaseProcessor.signal() }
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

        let task = CompressionTask(destination: destination)
        let probe = ConversionProbe<VideoInfo>()
        let conversion = Task {
            do {
                probe.store(.success(try await VideoTool.convert(
                    source: source,
                    destination: destination,
                    videoSettings: settings,
                    skipAudio: true,
                    overwrite: true,
                    task: task
                )))
            } catch {
                probe.store(.failure(error))
            }
        }

        await fulfillment(of: [processorEntered], timeout: 10)
        task.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(
            probe.hasFinished,
            "The conversion must not resume its caller while a public processor is in flight"
        )

        releaseProcessor.signal()
        await conversion.value
        XCTAssertTrue(probe.isCancellation, "Expected the cancelled conversion to throw CancellationError")
    }

    // visionOS reads through `AVAssetReaderTrackOutput` and rejects video
    // composition outright, so it never takes the asynchronous read path this
    // test covers. Cropping there throws `notSupportedOnVisionOS` instead.
    #if !os(visionOS)
    func testCancellationDuringCompositionReadsIsSerialized() async throws {
        let source = try fixture("chromecast.mp4")
        let settings = CompressionVideoSettings(
            codec: .h264,
            edit: [.crop(.init(size: CGSize(width: 640, height: 360)))]
        )

        // Establishes the premise: only a composition output reads off the
        // session queue, and `AVAssetReader` forbids `cancelReading()` running
        // concurrently with `copyNextSampleBuffer()`.
        let variables = try await VideoTool.initializeVideo(
            asset: AVAsset(url: source),
            videoSettings: settings
        )
        XCTAssertTrue(
            variables.videoOutput is AVAssetReaderVideoCompositionOutput,
            "Cropping must route through a video composition output for this test to cover the race"
        )

        // The fixture runs 15 seconds, so every cancellation below lands while
        // the reader is still active. Staggering the delay walks the cancellation
        // across startup and steady-state reading.
        for iteration in 0 ..< 8 {
            let destination = try outputURL("composition-cancellation-\(iteration).mov")
            let task = CompressionTask(destination: destination)
            let probe = ConversionProbe<VideoInfo>()

            let conversion = Task {
                do {
                    probe.store(.success(try await VideoTool.convert(
                        source: source,
                        destination: destination,
                        videoSettings: settings,
                        skipAudio: true,
                        overwrite: true,
                        task: task
                    )))
                } catch {
                    probe.store(.failure(error))
                }
            }

            let started = try await waitForConversionStart(task)
            XCTAssertTrue(started, "Conversion \(iteration) never left preparation")
            try await Task.sleep(nanoseconds: UInt64(iteration + 1) * 5_000_000)
            task.cancel()

            await conversion.value
            XCTAssertTrue(probe.isCancellation, "Expected conversion \(iteration) to report cancellation")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: destination.path),
                "A cancelled conversion must not publish its destination"
            )
        }
    }
    #endif

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

        _ = try await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            cacheDirectory: cache,
            overwrite: true,
            deleteSourceFile: true
        )

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
        let task = CompressionTask(destination: destination)
        let conversion = Task {
            try await AudioTool.convert(
                source: source,
                destination: destination,
                settings: .init(codec: .aac, bitrate: .value(96_000)),
                overwrite: true,
                deleteSourceFile: true,
                task: task
            )
        }

        // The replacement has to land after the pipeline opened its source,
        // which is what `.started` used to signal.
        let started = try await waitForConversionStart(task)
        XCTAssertTrue(started, "Audio conversion never left preparation")
        replacer.replace()
        _ = try await conversion.value

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
        let task = CompressionTask(destination: destination)
        let conversion = Task {
            try await VideoTool.convert(
                source: source,
                destination: destination,
                videoSettings: .init(
                    codec: .h264,
                    bitrate: .encoder,
                    edit: [.cut(from: 0, to: 1)]
                ),
                skipAudio: true,
                overwrite: true,
                deleteSourceFile: true,
                task: task
            )
        }

        // The replacement has to land after the pipeline opened its source,
        // which is what `.started` used to signal.
        let started = try await waitForConversionStart(task)
        XCTAssertTrue(started, "Video conversion never left preparation")
        replacer.replace()
        _ = try await conversion.value

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

        _ = try await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(
                codec: .h264,
                bitrate: .encoder,
                edit: [.cut(from: 0, to: 1)]
            ),
            skipAudio: true,
            overwrite: true
        )

        XCTAssertNotEqual(try Data(contentsOf: destination), sentinelData)
        let videoTrack = await AVAsset(url: destination).getFirstTrack(withMediaType: .video)
        XCTAssertNotNil(videoTrack)
    }

    /// An inactive progress queue must not keep a finished conversion alive.
    ///
    /// The 1.x version of this test anchored its lifetime probe in the public
    /// terminal callback. With that callback gone, the probe rides in the frame
    /// processor instead — also retained by the session for the conversion's
    /// whole lifetime, so it leaks in exactly the same circumstances.
    func testProgressQueueDoesNotRetainCompletedSession() async throws {
        let source = try fixture("chromecast.mp4")
        let destination = try outputURL("progress-retention.mov")
        let released = expectation(description: "processor lifetime released")
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

            _ = try await VideoTool.convert(
                source: source,
                destination: destination,
                videoSettings: .init(
                    codec: .h264,
                    bitrate: .encoder,
                    edit: [
                        .cut(from: 0, to: 1),
                        .process(.sampleBuffer { [probe] sample in
                            _ = probe
                            return sample
                        })
                    ]
                ),
                skipAudio: true,
                overwrite: true,
                progressQueue: inactiveQueue
            )
        }

        await fulfillment(of: [released], timeout: 5)
        XCTAssertNil(weakProbe)
    }

    /// A progress queue that never runs must not stall the conversion itself.
    func testAudioConversionCompletesWithAnInactiveProgressQueue() async throws {
        let source = try fixture("440Hz.mp3")
        let destination = try outputURL("progress-retention.m4a")
        let inactiveQueue = DispatchQueue(
            label: "MediaToolSwiftTests.inactive-audio-progress",
            attributes: .initiallyInactive
        )
        defer { inactiveQueue.activate() }

        _ = try await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            overwrite: true,
            progressQueue: inactiveQueue
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
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

        let task = CompressionTask(destination: destination)
        let probe = ConversionProbe<AudioInfo>()
        let conversion = Task {
            do {
                probe.store(.success(try await AudioTool.convert(
                    source: source,
                    destination: destination,
                    settings: .init(codec: .aac, bitrate: .value(96_000)),
                    overwrite: true,
                    deleteSourceFile: true,
                    task: task
                )))
            } catch {
                probe.store(.failure(error))
            }
        }

        task.progress.cancel()
        task.cancel()
        task.cancel()
        task.writingProgress.cancel()

        await conversion.value
        // A second terminal event would resume the continuation twice, which
        // traps rather than merely recording an extra state, so the sleep gives
        // any stray delivery a chance to land before the test ends.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(probe.isCancellation)
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

        let task = CompressionTask(destination: destination)
        let probe = ConversionProbe<VideoInfo>()
        let conversion = Task {
            do {
                probe.store(.success(try await VideoTool.convert(
                    source: source,
                    destination: destination,
                    videoSettings: .init(codec: .hevc, bitrate: .encoder),
                    skipAudio: true,
                    overwrite: true,
                    deleteSourceFile: true,
                    task: task
                )))
            } catch {
                probe.store(.failure(error))
            }
        }

        task.progress.cancel()
        task.cancel()
        task.cancel()
        task.writingProgress.cancel()

        await conversion.value
        // A second terminal event would trap on a double continuation resume.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(probe.isCancellation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), sentinelData)
    }

    /// A `CompressionTask` tracks one terminal outcome for its lifetime, so a
    /// reused task must be rejected. Before this was enforced, the second
    /// conversion had every terminal claim refused, delivered no state, and hung
    /// forever with no way to cancel it.
    /// A task built for one destination but handed to a conversion writing
    /// another must report the file actually being written.
    ///
    /// Audio is the sharpest case: `VideoProgress.configureWritingProgress` is
    /// what normally corrects `fileURL`, and audio conversions never build one,
    /// so nothing else would ever fix it. The same gap exists for video outputs
    /// below `FileObserverConfig.minimalFileLenght`.
    func testWritingProgressReportsTheDestinationActuallyWritten() async throws {
        let source = try fixture("440Hz.mp3")
        let stale = try outputURL("task-destination-stale.m4a")
        let actual = try outputURL("task-destination-actual.m4a")

        let task = CompressionTask(destination: stale)
        XCTAssertEqual(task.writingProgress.fileURL, stale)

        _ = try await AudioTool.convert(
            source: source,
            destination: actual,
            settings: CompressionAudioSettings(codec: .aac, bitrate: .value(96_000)),
            overwrite: true,
            task: task
        )

        XCTAssertEqual(task.writingProgress.fileURL, actual)
        XCTAssertTrue(FileManager.default.fileExists(atPath: actual.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testReusingACompressionTaskIsRejectedRatherThanHanging() async throws {
        let source = try fixture("440Hz.mp3")
        let first = try outputURL("task-reuse-1.m4a")
        let second = try outputURL("task-reuse-2.m4a")
        let settings = CompressionAudioSettings(codec: .aac, bitrate: .value(96_000))

        let task = CompressionTask(destination: first)
        _ = try await AudioTool.convert(
            source: source,
            destination: first,
            settings: settings,
            overwrite: true,
            task: task
        )

        do {
            _ = try await AudioTool.convert(
                source: source,
                destination: second,
                settings: settings,
                overwrite: true,
                task: task
            )
            XCTFail("Reusing a completed task must not start a second conversion")
        } catch let error as CompressionError {
            XCTAssertEqual(error, .taskAlreadyUsed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    /// The same latch applies to a task already used by a video conversion, and
    /// to one still in flight.
    func testReusingAnInFlightCompressionTaskIsRejected() async throws {
        let source = try fixture("oludeniz.MOV")
        let first = try outputURL("task-inflight-1.mov")
        let second = try outputURL("task-inflight-2.mov")

        let task = CompressionTask(destination: first)
        let conversion = Task {
            try await VideoTool.convert(
                source: source,
                destination: first,
                videoSettings: .init(codec: .hevc, bitrate: .encoder),
                skipAudio: true,
                overwrite: true,
                task: task
            )
        }

        let started = try await waitForConversionStart(task)
        XCTAssertTrue(started, "Video conversion never left preparation")

        do {
            _ = try await VideoTool.convert(
                source: source,
                destination: second,
                skipAudio: true,
                overwrite: true,
                task: task
            )
            XCTFail("Reusing an in-flight task must not start a second conversion")
        } catch let error as CompressionError {
            XCTAssertEqual(error, .taskAlreadyUsed)
        }

        task.cancel()
        _ = try? await conversion.value
    }

    /// A cancelled Task must stop thumbnail generation rather than waiting for
    /// every `AVAssetImageGenerator` request to finish.
    /// Cancellation that is already pending when the call begins.
    ///
    /// `withTaskCancellationHandler` fires `onCancel` before running the
    /// operation in this case, so `cancelAllCGImageGeneration()` reaches a
    /// generator with nothing queued and cancels nothing. The early
    /// `Task.checkCancellation()` is what makes this path skip the decode
    /// rather than doing all the work and discarding it.
    func testThumbnailGenerationHonoursCancellationRequestedBeforeItStarts() async throws {
        let source = try fixture("oludeniz.MOV")
        let asset = AVAsset(url: source)

        let generation = Task {
            try await VideoTool.thumbnailImages(
                for: asset,
                at: Array(stride(from: 0.0, to: 3.0, by: 0.05))
            )
        }
        generation.cancel()

        do {
            _ = try await generation.value
            XCTFail("Expected cancelled thumbnail generation to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// Cancellation that arrives after generation is under way, which is the
    /// path the `onCancel` handler actually exists for. The wait only decides
    /// which path is taken; the assertion holds either way, so this cannot
    /// flake on a slow machine.
    func testThumbnailGenerationHonoursCancellationDuringGeneration() async throws {
        let source = try fixture("oludeniz.MOV")
        let asset = AVAsset(url: source)

        let generation = Task {
            try await VideoTool.thumbnailImages(
                for: asset,
                at: Array(stride(from: 0.0, to: 3.0, by: 0.01)),
                timeToleranceBefore: .zero,
                timeToleranceAfter: .zero
            )
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        generation.cancel()

        do {
            _ = try await generation.value
            XCTFail("Expected cancelled thumbnail generation to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// Cancellation arriving while the *last* thumbnail is being edited and
    /// written. `encodeThumbnails` checks before each frame, so with a single
    /// request there is no later per-frame check to catch it and the call
    /// reported success for a cancelled task.
    ///
    /// Blocking the public `ImageProcessor` is what makes the window
    /// deterministic rather than timing-dependent: the task is cancelled while
    /// the only frame is provably in flight.
    func testThumbnailEncodingHonoursCancellationDuringTheFinalFrame() async throws {
        let source = try fixture("oludeniz.MOV")
        let asset = AVAsset(url: source)
        let output = try outputURL("thumbnail-cancel-final-frame.png")

        let processorEntered = expectation(description: "image processor entered")
        processorEntered.assertForOverFulfill = false
        let releaseProcessor = DispatchSemaphore(value: 0)
        defer { releaseProcessor.signal() }
        let settings = ImageSettings(
            format: .png,
            edit: [
                .imageProcessing({ ciImage, cgImage, _, _ in
                    processorEntered.fulfill()
                    releaseProcessor.wait()
                    return (ciImage, cgImage)
                })
            ]
        )

        let generation = Task {
            try await VideoTool.thumbnailFiles(
                of: asset,
                at: [VideoThumbnailRequest(time: 0, url: output)],
                settings: settings
            )
        }

        await fulfillment(of: [processorEntered], timeout: 10)
        generation.cancel()
        releaseProcessor.signal()

        do {
            _ = try await generation.value
            XCTFail("Expected cancellation during the final encode to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testConcurrentCancellationStressPreservesEverySource() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let cancellationQueue = DispatchQueue(
            label: "MediaToolSwiftTests.concurrent-cancellation",
            attributes: .concurrent
        )
        var cancellations: [ConversionProbe<Bool>] = []
        var conversions: [Task<Void, Never>] = []
        var sources: [URL] = []
        var destinations: [URL] = []

        // Each probe stores `Bool` rather than the conversion's own info type so
        // audio and video sessions can share one result list; only cancellation
        // is asserted.
        func record(_ probe: ConversionProbe<Bool>, _ body: @escaping @Sendable () async throws -> Void) -> Task<Void, Never> {
            Task {
                do {
                    try await body()
                    probe.store(.success(true))
                } catch {
                    probe.store(.failure(error))
                }
            }
        }

        for index in 0 ..< 2 {
            let source = try outputURL("concurrent-audio-\(index).mov")
            let destination = try outputURL("concurrent-audio-\(index).m4a")
            try FileManager.default.copyItem(at: fixture, to: source)
            let task = CompressionTask(destination: destination)
            let probe = ConversionProbe<Bool>()
            conversions.append(record(probe) {
                _ = try await AudioTool.convert(
                    source: source,
                    destination: destination,
                    settings: .init(codec: .aac, bitrate: .value(96_000)),
                    overwrite: true,
                    deleteSourceFile: true,
                    task: task
                )
            })
            cancellationQueue.async {
                task.progress.cancel()
                task.cancel()
                task.cancel()
                task.writingProgress.cancel()
            }
            cancellations.append(probe)
            sources.append(source)
            destinations.append(destination)
        }

        for index in 0 ..< 2 {
            let source = try outputURL("concurrent-video-source-\(index).mov")
            let destination = try outputURL("concurrent-video-output-\(index).mov")
            try FileManager.default.copyItem(at: fixture, to: source)
            let task = CompressionTask(destination: destination)
            let probe = ConversionProbe<Bool>()
            conversions.append(record(probe) {
                _ = try await VideoTool.convert(
                    source: source,
                    destination: destination,
                    videoSettings: .init(codec: .hevc, bitrate: .encoder),
                    skipAudio: true,
                    overwrite: true,
                    deleteSourceFile: true,
                    task: task
                )
            })
            cancellationQueue.async {
                task.progress.cancel()
                task.cancel()
                task.cancel()
                task.writingProgress.cancel()
            }
            cancellations.append(probe)
            sources.append(source)
            destinations.append(destination)
        }

        for conversion in conversions {
            await conversion.value
        }
        // A duplicate terminal event traps on a double continuation resume.
        try await Task.sleep(nanoseconds: 100_000_000)

        for index in cancellations.indices {
            XCTAssertTrue(cancellations[index].isCancellation, "session \(index) did not report cancellation")
            XCTAssertTrue(FileManager.default.fileExists(atPath: sources[index].path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destinations[index].path))
        }
    }
}
