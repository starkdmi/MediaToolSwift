import AVFoundation
@preconcurrency import MediaToolSwift
import XCTest

private final class OrdinaryClientState {
    var callbackCount = 0
}

/// The counterpart of `OrdinaryClientState` for the closures that became
/// `@Sendable`. A real client migrates to a synchronized box exactly like this
/// one, since these closures run off the caller's isolation domain.
private final class SynchronizedClientState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class Swift6ClientCompilationTests: XCTestCase {
    /// This helper is intentionally compile-only. It verifies that a Swift 6 UI
    /// client can call the public APIs with inline callbacks, while actor state
    /// updates make their required hop explicit.
    ///
    /// It also pins the boundary: every public processor closure — frame,
    /// bitrate, size, and image — is `@Sendable` and rejects unsynchronized
    /// captures. Note that `@preconcurrency import` does not soften them: the
    /// attribute is part of the function type, not a conformance.
    private nonisolated func compilePublicCallbackUsage(
        source: URL,
        destination: URL,
        asset: AVAsset
    ) async throws {
        let imageState = SynchronizedClientState()
        let frameState = SynchronizedClientState()
        let bitrateState = SynchronizedClientState()
        let sizeState = SynchronizedClientState()
        let videoCallbackState = OrdinaryClientState()
        let audioCallbackState = OrdinaryClientState()
        let thumbnailState = OrdinaryClientState()
        let imageProcessor: ImageProcessor = { ciImage, cgImage, _, _ in
            imageState.increment()
            return (ciImage, cgImage)
        }
        let frameProcessor = VideoFrameProcessor.sampleBuffer {
            frameState.increment()
            return $0
        }
        let settings = CompressionVideoSettings(
            bitrate: .dynamic {
                bitrateState.increment()
                return max($0 / 2, 1)
            },
            size: .dynamic {
                sizeState.increment()
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
