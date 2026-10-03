import AVFoundation
import XCTest
@testable import MediaToolSwift

final class MediaBoundarySafetyTests: XCTestCase {
    private static let mediaDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("media")

    private func fixture(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let url = Self.mediaDirectory.appendingPathComponent(name)
        return try XCTUnwrap(
            FileManager.default.fileExists(atPath: url.path) ? url : nil,
            "Required fixture is missing: \(name)",
            file: file,
            line: line
        )
    }

    /// `AVAssetWriterInput.init` raises `NSInvalidArgumentException` -
    /// "AVVideoCompressionPropertiesKey dictionary must specify a positive value
    /// for AVVideoAverageBitRateKey" - when the bitrate is not positive.
    /// `.source` therefore cannot forward an unknown (zero) source data rate to
    /// the encoder, and has to fail with a typed error instead. This is a fix
    /// rather than an optional strictness change; do not relax it back.
    func testVideoBitrateRejectsSourceOptionWhenSourceDataRateIsUnknown() {
        let calculator = VideoBitrateCalculator()
        let size = CGSize(width: 1920, height: 1080)

        XCTAssertThrowsError(
            try calculator.calculate(
                bitrateOption: .source,
                sourceBitrate: 0,
                targetSize: size,
                sourceSize: size,
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

    /// Case insensitivity, diacritic insensitivity, and width insensitivity are
    /// independent properties, and only the first is a real filesystem
    /// behavior. Names that differ by diacritics or character width are
    /// distinct entries on every supported volume, so they must not share a
    /// destination reservation.
    func testDestinationReservationKeepsDiacriticAndWidthVariantsDistinct() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-reserve-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Holding all three reservations at once fails if any two share a key.
        let plain = try FileOutputTransaction(
            destination: directory.appendingPathComponent("resume.mov"),
            overwrite: false
        )
        defer { plain.discard() }

        let accented = try FileOutputTransaction(
            destination: directory.appendingPathComponent("résumé.mov"),
            overwrite: false
        )
        defer { accented.discard() }

        let fullWidth = try FileOutputTransaction(
            destination: directory.appendingPathComponent("ｒｅｓｕｍｅ.mov"),
            overwrite: false
        )
        defer { fullWidth.discard() }

        XCTAssertNotEqual(plain.destinationURL, accented.destinationURL)
        XCTAssertNotEqual(plain.destinationURL, fullWidth.destinationURL)
    }

    /// The composed and decomposed spellings of one name address the same
    /// filesystem entry, so they must continue to share a reservation.
    func testDestinationReservationTreatsUnicodeNormalizationAsOneName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-reserve-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let composed = "résumé.mov".precomposedStringWithCanonicalMapping
        let decomposed = "résumé.mov".decomposedStringWithCanonicalMapping
        // `String` equality is canonical, so compare the encoded bytes to prove
        // the two spellings really are different on disk.
        XCTAssertNotEqual(
            Array(composed.utf8),
            Array(decomposed.utf8),
            "fixture must exercise both normal forms"
        )

        let first = try FileOutputTransaction(
            destination: directory.appendingPathComponent(composed),
            overwrite: false
        )
        defer { first.discard() }

        XCTAssertThrowsError(
            try FileOutputTransaction(
                destination: directory.appendingPathComponent(decomposed),
                overwrite: false
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .destinationFileExists)
        }
    }

    func testVideoSizeCalculationRejectsNonFiniteRotation() {
        let calculator = VideoSizeCalculator()
        for angle in [Float.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(
                try calculator.calculate(
                    settings: .original,
                    sourceSize: CGSize(width: 1920, height: 1080),
                    operations: [.rotate(.angle(angle))],
                    orientation: .landscape
                )
            ) { error in
                XCTAssertEqual(error as? CompressionError, .invalidVideoSize)
            }
        }
    }

    func testVideoCropRejectsRectanglesLargerThanTheSource() {
        let calculator = VideoSizeCalculator()
        XCTAssertThrowsError(
            try calculator.calculate(
                settings: .original,
                sourceSize: CGSize(width: 1920, height: 1080),
                operations: [
                    .crop(Crop(rect: CGRect(x: 0, y: 0, width: 2000, height: 100)))
                ],
                orientation: .landscape
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .croppingOutOfBounds)
        }
    }

    /// A crop that fits the source but is positioned so it overhangs an edge is
    /// accepted, matching released behavior: the encoder pads the uncovered
    /// region rather than failing. Verified end to end against real media - a
    /// 400x400 crop starting past the right edge of a 1280x720 source still
    /// produces a valid 400x400 movie.
    func testVideoCropAllowsRectanglesOverhangingSourceEdges() throws {
        let calculator = VideoSizeCalculator()
        let result = try calculator.calculate(
            settings: .original,
            sourceSize: CGSize(width: 1920, height: 1080),
            operations: [
                .crop(Crop(rect: CGRect(x: 1900, y: 0, width: 100, height: 100)))
            ],
            orientation: .landscape
        )
        XCTAssertEqual(result.cropRect, CGRect(x: 1900, y: 0, width: 100, height: 100))
        XCTAssertEqual(result.targetSize, CGSize(width: 100, height: 100))
    }

    func testVideoFormatDescriptionReadsPixelAspectRatio() throws {
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_PixelAspectRatio: [
                kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing: 40,
                kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing: 33
            ]
        ]
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 720,
            height: 480,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )

        XCTAssertEqual(status, noErr)
        XCTAssertEqual(
            try XCTUnwrap(description).pixelAspectRatio,
            VideoPixelAspectRatio(horizontalSpacing: 40, verticalSpacing: 33)
        )
    }

    func testFileSizeObserverCallbackCanFinishObserver() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-observer-\(UUID().uuidString)")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let callbackFinished = expectation(description: "observer callback returned")
        let holder = LockedValue<FileSizeObserver?>(nil)
        let observer = FileSizeObserver(
            url: url,
            queue: DispatchQueue(label: "MediaToolSwiftTests.FileSizeObserver")
        ) { _ in
            holder.read()?.finish()
            callbackFinished.fulfill()
        }
        holder.set(observer)

        // The throwing FileHandle API requires 13.4, above the package's iOS and
        // tvOS deployment targets, so mirror `FileHandle.seekToFileEnd()`.
        let writer = try FileHandle(forWritingTo: url)
        let payload = Data(repeating: 0xA5, count: 64)
        if #available(macOS 11, iOS 13.4, tvOS 13.4, *) {
            try writer.seekToEnd()
            try writer.write(contentsOf: payload)
            try writer.synchronize()
            try writer.close()
        } else {
            _ = writer.seekToEndOfFile()
            writer.write(payload)
            writer.synchronizeFile()
            writer.closeFile()
        }

        wait(for: [callbackFinished], timeout: 2)
        observer.finish()
    }

    func testCustomImageFormatRegistrationIsReentrantAndHashStable() throws {
        let identifier = "tests.custom.\(UUID().uuidString)"
        let format = ImageFormat.custom(identifier)
        var formats: Set<ImageFormat> = [format]
        let first = ReentrantCustomImageFormat(
            identifier: identifier,
            type: "tests.custom.first" as CFString,
            payload: Data("first-payload".utf8)
        )

        ImageFormat.registerCustomFormat(first)
        XCTAssertTrue(formats.contains(format))

        let source = try fixture("starkdev.png")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-custom-\(UUID().uuidString)")
        try Data("previous-destination".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        let info = try ImageTool.convert(
            source: source,
            destination: destination,
            settings: .init(format: format, size: .fit(CGSize(width: 32, height: 32))),
            overwrite: true
        )
        XCTAssertEqual(try Data(contentsOf: destination), Data("first-payload".utf8))
        XCTAssertEqual(info.format, format)
        XCTAssertEqual(info.size, first.writtenSize())

        let replacement = ReentrantCustomImageFormat(
            identifier: identifier,
            type: "tests.custom.replacement" as CFString,
            payload: Data("replacement-payload".utf8)
        )
        ImageFormat.registerCustomFormat(replacement)
        XCTAssertTrue(formats.contains(format))
        formats.remove(format)
        XCTAssertTrue(formats.isEmpty)
    }

    func testAudioConfigurationRejectsExceptionRaisingSampleRates() async throws {
        let asset = AVAsset(url: try fixture("440Hz.mp3"))
        let loadedTrack = await asset.getFirstTrack(withMediaType: .audio)
        let track = try XCTUnwrap(loadedTrack)

        for sampleRate in [-1, 0, 7_999, 192_001] {
            do {
                _ = try await AudioTrackConfiguration.makeVariables(
                    track: track,
                    settings: .init(sampleRate: sampleRate)
                )
                XCTFail("Invalid sample rate \(sampleRate) was accepted")
            } catch let error as CompressionError {
                XCTAssertEqual(error, .failedToReadAudio)
            }
        }
    }

    func testImagePublicBoundariesRejectUnsafeGeometry() throws {
        let source = try fixture("starkdev.png")
        let invalidSettings: [ImageSettings] = [
            .init(size: .fit(CGSize(width: CGFloat.nan, height: 10)), preferredFramework: .cgImage),
            .init(size: .fit(CGSize(width: 10, height: -CGFloat.infinity)), preferredFramework: .vImage),
            .init(size: .crop(options: Crop(rect: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)))),
            .init(size: .crop(options: Crop(size: CGSize(width: -1, height: 10)))),
            .init(edit: [.rotate(.angle(Float.nan))], preferredFramework: .vImage)
        ]

        for settings in invalidSettings {
            XCTAssertThrowsError(try ImageTool.decode(source: source, settings: settings)) { error in
                XCTAssertEqual(error as? CompressionError, .failedToReadImage)
            }
        }

        let image = try ImageTool.decode(source: source)
        let edited = ImageTool.edit(
            image,
            settings: .init(size: .fit(CGSize(width: CGFloat.nan, height: 10)))
        )
        XCTAssertEqual(edited.frames, image.frames)
        XCTAssertEqual(edited.size, CGSize.zero)

        let cgDecoded = try ImageTool.decode(
            source: source,
            settings: .init(preferredFramework: .cgImage)
        )
        let cgImage = try XCTUnwrap(cgDecoded.frames.first?.cgImage)
        XCTAssertNil(cgImage.resizing(to: CGSize(width: CGFloat.nan, height: 10)))
        XCTAssertNil(cgImage.scaling(to: CGSize(width: 10, height: -1)))
        XCTAssertNil(cgImage.rotating(by: .angle(.infinity)))

        let ciImage = CIImage(cgImage: cgImage)
        XCTAssertEqual(
            ciImage.resizing(to: CGSize(width: CGFloat.nan, height: 10)).extent,
            ciImage.extent
        )
        XCTAssertEqual(ciImage.rotating(by: .angle(.nan)).extent, ciImage.extent)
    }

    /// The numeric guards must reject before the asset is ever touched, which is
    /// why the fixture URL does not exist: reaching the asset would surface
    /// `videoTrackNotFound` instead.
    func testThumbnailPublicBoundaryRejectsUnsafeNumericValuesBeforeAssetAccess() async {
        let missingAsset = AVAsset(
            url: URL(fileURLWithPath: "/definitely-missing-mediatoolswift-fixture.mp4")
        )

        let invalidCalls: [() async throws -> Void] = [
            {
                _ = try await VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [0],
                    size: CGSize(width: CGFloat.nan, height: 10)
                )
            },
            {
                _ = try await VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [Double.nan]
                )
            },
            {
                _ = try await VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [0],
                    timeToleranceBefore: .nan
                )
            }
        ]

        for invalidCall in invalidCalls {
            do {
                try await invalidCall()
                XCTFail("Expected the numeric guard to reject this call")
            } catch {
                XCTAssertEqual(error as? CompressionError, .failedToGenerateThumbnails)
            }
        }
    }

    func testThumbnailFilesRejectsUnsafeCropGeometry() async {
        let missingAsset = AVAsset(
            url: URL(fileURLWithPath: "/definitely-missing-mediatoolswift-fixture.mp4")
        )

        do {
            _ = try await VideoTool.thumbnailFiles(
                of: missingAsset,
                at: [],
                settings: .init(
                    size: .crop(
                        options: Crop(rect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10))
                    )
                )
            )
            XCTFail("Invalid crop geometry must be rejected before the asset is read")
        } catch {
            XCTAssertEqual(error as? CompressionError, .failedToGenerateThumbnails)
        }
    }

    func testAudioProgressRejectsNonFiniteSampleTimestamps() {
        XCTAssertNil(
            audioProgressCompletedUnitCount(
                sampleTime: .invalid,
                duration: CMTime(seconds: 10, preferredTimescale: 600),
                range: nil,
                total: 100
            )
        )
        XCTAssertNil(
            audioProgressCompletedUnitCount(
                sampleTime: .positiveInfinity,
                duration: CMTime(seconds: 10, preferredTimescale: 600),
                range: nil,
                total: 100
            )
        )
        XCTAssertEqual(
            audioProgressCompletedUnitCount(
                sampleTime: CMTime(seconds: 6, preferredTimescale: 600),
                duration: CMTime(seconds: 10, preferredTimescale: 600),
                range: CMTimeRange(
                    start: CMTime(seconds: 1, preferredTimescale: 600),
                    duration: CMTime(seconds: 10, preferredTimescale: 600)
                ),
                total: 100
            ),
            50
        )
    }
}

private final class ReentrantCustomImageFormat: CustomImageFormat {
    private let lock = NSLock()
    private let storedIdentifier: String
    private let type: CFString
    private let payload: Data
    private var size: CGSize?

    init(identifier: String, type: CFString, payload: Data) {
        storedIdentifier = identifier
        self.type = type
        self.payload = payload
    }

    var identifier: String {
        // Registration must never hold the global registry lock while asking
        // custom code for its identifier.
        _ = ImageFormat.registeredFormats
        return storedIdentifier
    }

    var utType: CFString? { type }
    var isAnimationSupported: Bool { false }
    var isLowQuality: Bool { false }

    func write(
        frames: [ImageFrame],
        to url: URL,
        skipMetadata: Bool,
        settings: ImageSettings,
        orientation: CGImagePropertyOrientation?,
        isHDR: Bool?,
        primaryIndex: Int,
        metadata: [CFString: Any]?
    ) throws {
        lock.lock()
        size = frames[primaryIndex].size
        lock.unlock()
        try payload.write(to: url)
    }

    func writtenSize() -> CGSize? {
        lock.lock()
        defer { lock.unlock() }
        return size
    }
}
