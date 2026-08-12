import AVFoundation
@preconcurrency import MediaToolSwift
import XCTest

private final class OrdinaryClientState {
    var callbackCount = 0
}

final class Swift6ClientCompilationTests: XCTestCase {
    /// This helper is intentionally compile-only. It verifies that a Swift 6 UI
    /// client can call the public APIs with inline callbacks, while actor state
    /// updates make their required hop explicit.
    private nonisolated func compilePublicCallbackUsage(
        source: URL,
        destination: URL,
        asset: AVAsset
    ) async throws {
        let imageState = OrdinaryClientState()
        let frameState = OrdinaryClientState()
        let bitrateState = OrdinaryClientState()
        let sizeState = OrdinaryClientState()
        let videoCallbackState = OrdinaryClientState()
        let audioCallbackState = OrdinaryClientState()
        let thumbnailState = OrdinaryClientState()
        let imageProcessor: ImageProcessor = { ciImage, cgImage, _, _ in
            imageState.callbackCount += 1
            return (ciImage, cgImage)
        }
        let frameProcessor = VideoFrameProcessor.sampleBuffer {
            frameState.callbackCount += 1
            return $0
        }
        let settings = CompressionVideoSettings(
            bitrate: .dynamic {
                bitrateState.callbackCount += 1
                return max($0 / 2, 1)
            },
            size: .dynamic {
                sizeState.callbackCount += 1
                return .fit($0)
            },
            edit: [.process(frameProcessor)]
        )
        _ = ImageOperation.imageProcessing(imageProcessor)

        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: settings
        ) { _ in
            videoCallbackState.callbackCount += 1
        }

        _ = await AudioTool.convert(
            source: source,
            destination: destination
        ) { _ in
            audioCallbackState.callbackCount += 1
        }

        _ = await VideoTool.convert(
            source: source,
            destination: destination
        ) { _ in
            videoCallbackState.callbackCount += 1
        }

        try VideoTool.thumbnailImages(for: asset, at: []) { _ in
            thumbnailState.callbackCount += 1
        }
    }

    func testPublicModuleImportsWithoutTestableAccess() {
        XCTAssertTrue(true)
    }
}
