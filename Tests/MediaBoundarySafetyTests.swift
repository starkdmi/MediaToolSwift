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

        let writer = try FileHandle(forWritingTo: url)
        try writer.seekToEnd()
        try writer.write(contentsOf: Data(repeating: 0xA5, count: 64))
        try writer.synchronize()
        try writer.close()

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

    func testThumbnailPublicBoundaryRejectsUnsafeNumericValuesBeforeAssetAccess() {
        let missingAsset = AVAsset(
            url: URL(fileURLWithPath: "/definitely-missing-mediatoolswift-fixture.mp4")
        )

        let invalidCalls: [() throws -> Void] = [
            {
                try VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [0],
                    size: CGSize(width: CGFloat.nan, height: 10),
                    completion: { _ in }
                )
            },
            {
                try VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [Double.nan],
                    completion: { _ in }
                )
            },
            {
                try VideoTool.thumbnailImages(
                    for: missingAsset,
                    at: [0],
                    timeToleranceBefore: .nan,
                    completion: { _ in }
                )
            }
        ]

        for invalidCall in invalidCalls {
            XCTAssertThrowsError(try invalidCall()) { error in
                XCTAssertEqual(error as? CompressionError, .failedToGenerateThumbnails)
            }
        }
    }

    func testThumbnailFilesRejectsUnsafeCropGeometry() {
        let missingAsset = AVAsset(
            url: URL(fileURLWithPath: "/definitely-missing-mediatoolswift-fixture.mp4")
        )
        let result = LockedValue<Result<[VideoThumbnailFile], CompressionError>?>(nil)

        VideoTool.thumbnailFiles(
            of: missingAsset,
            at: [],
            settings: .init(
                size: .crop(
                    options: Crop(rect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10))
                )
            )
        ) { value in
            result.set(value)
        }

        switch result.read() {
        case .failure(let error):
            XCTAssertEqual(error, .failedToGenerateThumbnails)
        case .success, .none:
            XCTFail("Invalid crop geometry must fail synchronously")
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
