import AVFoundation
import XCTest
@testable import MediaToolSwift

#if os(macOS)
final class VideoHDRBitDepthTests: XCTestCase {
    private static let mediaDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("media")

    func testHDRCompatibilityRejectsKnownEightBitCodecAndProfileChoices() throws {
        let resolver = VideoCodecResolver()
        let unsupportedCodec = AVVideoCodecType(rawValue: "unsupported-mediatoolswift-codec")
        XCTAssertThrowsError(
            try resolver.resolve(
                requestedCodec: unsupportedCodec,
                sourceCodec: .hevc,
                sourceHasAlpha: false,
                preserveAlphaRequested: false
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .invalidVideoCodec)
        }
        XCTAssertThrowsError(
            try VideoCodecResolver.validateHighBitDepthCompatibility(
                codec: unsupportedCodec,
                profile: nil
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .invalidVideoCodec)
        }

        let invalidChoices: [(AVVideoCodecType, CompressionVideoProfile?)] = [
            (.h264, nil),
            (.jpeg, nil),
            (.hevc, .hevcMain),
            (.hevc, .h264Baseline),
            (.hevc, .h264Main),
            (.hevc, .h264High)
        ]
        for (codec, profile) in invalidChoices {
            XCTAssertThrowsError(
                try VideoCodecResolver.validateHighBitDepthCompatibility(codec: codec, profile: profile)
            ) { error in
                XCTAssertEqual(error as? CompressionError, .invalidVideoCodec)
            }
        }

        XCTAssertNoThrow(
            try VideoCodecResolver.validateHighBitDepthCompatibility(codec: .hevc, profile: nil)
        )
        XCTAssertNoThrow(
            try VideoCodecResolver.validateHighBitDepthCompatibility(codec: .hevc, profile: .hevcMain10)
        )
        XCTAssertNoThrow(
            try VideoCodecResolver.validateHighBitDepthCompatibility(codec: .hevc, profile: .hevcMain42210)
        )
        XCTAssertThrowsError(
            try VideoCodecResolver.validateHighBitDepthCompatibility(
                codec: .hevc,
                profile: .value("custom-main10-profile")
            )
        )
        XCTAssertNoThrow(
            try VideoCodecResolver.validateHighBitDepthCompatibility(codec: .proRes422, profile: nil)
        )
    }

    func testHDRPipelineRejectsKnownIncompatibleOutputBeforeEncoding() async throws {
        let fixture = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")
        let source = try XCTUnwrap(
            FileManager.default.fileExists(atPath: fixture.path) ? fixture : nil,
            "Required fixture is missing: oludeniz.MOV"
        )
        let asset = AVAsset(url: source)

        do {
            _ = try await VideoTool.initializeVideo(
                asset: asset,
                videoSettings: .init(codec: .h264)
            )
            XCTFail("HDR H.264 output should have been rejected")
        } catch let error as CompressionError {
            XCTAssertEqual(error, .invalidVideoCodec)
        }

        do {
            _ = try await VideoTool.initializeVideo(
                asset: asset,
                videoSettings: .init(codec: .hevc, profile: .hevcMain)
            )
            XCTFail("HDR HEVC Main output should have been rejected")
        } catch let error as CompressionError {
            XCTAssertEqual(error, .invalidVideoCodec)
        }
    }

    func testHDRFrameProcessingPreservesEncodedBitDepth() async throws {
        guard ProcessInfo.processInfo.environment["MEDIATOOLSWIFT_EXTENDED_MEDIA"] == "1" else {
            throw XCTSkip("Set MEDIATOOLSWIFT_EXTENDED_MEDIA=1 to run extended media coverage")
        }

        let fixture = Self.mediaDirectory.appendingPathComponent("google_pixel_hdr.mp4")
        let source = try XCTUnwrap(
            FileManager.default.fileExists(atPath: fixture.path) ? fixture : nil,
            "Required fixture is missing: google_pixel_hdr.mp4"
        )

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwiftHDRTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let destination = outputDirectory.appendingPathComponent("processed-hdr.mov")
        let terminal = expectation(description: "HDR conversion terminal state")
        let terminalState = LockedValue<CompressionState?>(nil)

        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(
                bitrate: .value(4_000_000),
                edit: [
                    .cut(from: 0, to: 0.5),
                    .process(.image { image, _, _ in image })
                ]
            ),
            skipAudio: true,
            overwrite: true
        ) { state in
            switch state {
            case .completed, .failed, .cancelled:
                terminalState.set(state)
                terminal.fulfill()
            case .started:
                break
            }
        }

        await fulfillment(of: [terminal], timeout: 120)

        switch terminalState.read() {
        case .completed:
            break
        case .failed(let error):
            throw error
        case .cancelled:
            return XCTFail("HDR conversion was cancelled unexpectedly")
        case .started, .none:
            return XCTFail("HDR conversion did not report a terminal state")
        }

        let outputAsset = AVAsset(url: destination)
        let maybeOutputTrack = await outputAsset.getFirstTrack(withMediaType: .video)
        let outputTrack = try XCTUnwrap(maybeOutputTrack)
        let outputDescriptions = await outputTrack.getFormatDescriptions()
        let outputDescription = try XCTUnwrap(outputDescriptions.first)
        let encodedBitDepth = (
            CMFormatDescriptionGetExtension(
                outputDescription,
                extensionKey: kCMFormatDescriptionExtension_BitsPerComponent
            ) as? NSNumber
        )?.intValue

        XCTAssertTrue(outputDescription.isHDRVideo, "Encoded output lost its HDR transfer function")
        XCTAssertGreaterThanOrEqual(
            encodedBitDepth ?? 0,
            10,
            "Encoded output was reduced to an 8-bit codec profile"
        )
    }
}
#endif
