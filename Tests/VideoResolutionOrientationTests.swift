import AVFoundation
import XCTest
@testable import MediaToolSwift

/// `VideoInfo.resolution` must describe the frames a player displays: the
/// decoded first frame with the preferred track transform applied. Sources are
/// generated so the encoded and displayed dimensions always differ.
final class VideoResolutionOrientationTests: XCTestCase {
    /// Encoded dimensions of every generated source
    private static let encodedSize = CGSize(width: 160, height: 96)

    private var outputDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwiftResolutionTests-\(UUID().uuidString)", isDirectory: true)
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

    func testDisplayedSizeSnapsTransformsToTheNearestQuarterTurn() {
        let size = CGSize(width: 160, height: 96)
        let swapped = CGSize(width: 96, height: 160)

        XCTAssertEqual(size.displayed(with: .identity), size)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(rotationAngle: .pi / 2)), swapped)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(rotationAngle: -.pi / 2)), swapped)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(rotationAngle: .pi)), size)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(rotationAngle: .pi / 3)), swapped)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(rotationAngle: .pi / 6)), size)
        XCTAssertEqual(size.displayed(with: CGAffineTransform(scaleX: 1, y: -1)), size)
        XCTAssertEqual(
            size.displayed(with: CGAffineTransform(rotationAngle: .pi / 2).concatenating(CGAffineTransform(scaleX: -1, y: 1))),
            swapped
        )
        // Portrait track transform as written by cameras
        XCTAssertEqual(size.displayed(with: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0)), swapped)
    }

    #if !os(visionOS)
    // MARK: - Video composition path

    func testPortraitCropOnCompositionPathReportsDisplayedResolution() async throws {
        let info = try await convert(
            portrait: true,
            edit: [.crop(Crop(size: CGSize(width: 48, height: 64), aligment: .center))]
        )
        XCTAssertEqual(info.resolution, CGSize(width: 48, height: 64))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testPortraitCropOnCompositionPathWithRotationReportsDisplayedResolution() async throws {
        let info = try await convert(
            portrait: true,
            edit: [
                .crop(Crop(size: CGSize(width: 48, height: 64), aligment: .center)),
                .rotate(.clockwise)
            ]
        )
        XCTAssertEqual(info.resolution, CGSize(width: 64, height: 48))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testPortraitImageCompositionReportsDisplayedResolution() async throws {
        let info = try await convert(
            portrait: true,
            edit: [.process(.imageComposition { image, _, _ in image })]
        )
        XCTAssertEqual(info.resolution, CGSize(width: 96, height: 160))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testPortraitImageCompositionWithRotationReportsDisplayedResolution() async throws {
        let info = try await convert(
            portrait: true,
            edit: [
                .process(.imageComposition { image, _, _ in image }),
                .rotate(.counterClockwise)
            ]
        )
        XCTAssertEqual(info.resolution, CGSize(width: 160, height: 96))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testResizedPortraitCropOnCompositionPathReportsDisplayedResolution() async throws {
        let info = try await convert(
            portrait: true,
            size: .fit(CGSize(width: 32, height: 32)),
            edit: [
                .crop(Crop(size: CGSize(width: 48, height: 64), aligment: .center)),
                .process(.imageComposition { image, _, _ in image })
            ]
        )
        XCTAssertEqual(info.resolution, CGSize(width: 24, height: 32))
        try await assertResolutionMatchesFirstFrame(info)
    }
    #endif

    // MARK: - Track output path

    func testPortraitReencodeReportsDisplayedResolution() async throws {
        let info = try await convert(portrait: true, codec: .hevc, edit: [])
        XCTAssertEqual(info.resolution, CGSize(width: 96, height: 160))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testPortraitRotationReportsDisplayedResolution() async throws {
        let info = try await convert(portrait: true, edit: [.rotate(.clockwise)])
        XCTAssertEqual(info.resolution, CGSize(width: 160, height: 96))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testLandscapeRotationReportsDisplayedResolution() async throws {
        let info = try await convert(portrait: false, edit: [.rotate(.clockwise)])
        XCTAssertEqual(info.resolution, CGSize(width: 96, height: 160))
        try await assertResolutionMatchesFirstFrame(info)
    }

    func testLandscapeUpsideDownKeepsResolution() async throws {
        let info = try await convert(portrait: false, edit: [.rotate(.upsideDown)])
        XCTAssertEqual(info.resolution, CGSize(width: 160, height: 96))
        try await assertResolutionMatchesFirstFrame(info)
    }

    // MARK: - Helpers

    private func convert(
        portrait: Bool,
        codec: AVVideoCodecType? = nil,
        size: CompressionVideoSize = .original,
        edit: Set<VideoOperation>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> VideoInfo {
        let directory = try XCTUnwrap(outputDirectory, "Test output directory was not created", file: file, line: line)
        let source = directory.appendingPathComponent("source-\(UUID().uuidString).mov")
        let destination = directory.appendingPathComponent("output-\(UUID().uuidString).mov")
        try await Self.writeSource(to: source, portrait: portrait)

        return try await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(codec: codec, size: size, edit: edit),
            skipAudio: true,
            copyExtendedFileMetadata: false
        )
    }

    /// Compares the reported resolution with the decoded first frame and with
    /// the information read back from the written file
    private func assertResolutionMatchesFirstFrame(
        _ info: VideoInfo,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let asset = AVAsset(url: info.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let image = try await generator.firstImage()
        let decodedSize = CGSize(width: image.width, height: image.height)

        XCTAssertEqual(info.resolution, decodedSize, "Reported resolution differs from the displayed frame", file: file, line: line)

        let fileInfo = try await VideoTool.getInfo(source: info.url)
        XCTAssertEqual(info.resolution, fileInfo.resolution, "Reported resolution differs from the written file", file: file, line: line)
    }

    /// Writes a short H.264 clip with 160x96 encoded frames; a portrait clip
    /// carries a 90 degree track transform and displays as 96x160
    private static func writeSource(to url: URL, portrait: Bool) async throws {
        let width = Int(encodedSize.width)
        let height = Int(encodedSize.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        if portrait {
            input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: encodedSize.height, ty: 0)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)

        for frame in 0 ..< 10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(frame * 20), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}

private extension AVAssetImageGenerator {
    /// Decodes the frame at time zero
    func firstImage() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, result, error in
                if let image, result == .succeeded {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CompressionError.failedToReadVideo)
                }
            }
        }
    }
}
