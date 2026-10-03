import AVFoundation
import MediaToolSwift
import XCTest

/// Companion canary to `Swift6ClientCompilationTests`, kept in its own file for
/// two reasons that both matter to what it catches.
///
/// It uses a plain `import MediaToolSwift`, not `@preconcurrency`, so nothing
/// downgrades a sending diagnostic to a warning. And it calls from `@MainActor`
/// with the `AVAsset` held in a stored property rather than received as a
/// parameter — a parameter is in a disconnected region and can always be sent,
/// which is exactly why the other file's `nonisolated` helper missed this.
///
/// This is the shape a real UI client has: a view model owning an asset. It
/// compiles only while the thumbnail APIs inherit caller isolation.
@MainActor
final class MainActorClientCompilationTests: XCTestCase {
    private let asset = AVAsset(url: URL(fileURLWithPath: "/dev/null"))

    /// Compile-only: never run, and would throw if it were.
    private func compileMainActorThumbnailUsage() async throws {
        _ = try await VideoTool.thumbnailImages(for: asset, at: [0])

        _ = try await VideoTool.thumbnailFiles(
            of: asset,
            at: [],
            settings: ImageSettings(format: .png)
        )
    }

    func testMainActorClientUsageCompiles() {
        XCTAssertNotNil(asset)
    }
}
