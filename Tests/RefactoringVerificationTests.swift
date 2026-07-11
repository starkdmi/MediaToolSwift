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

    func testAudioConversionHonorsDeleteSourceAndCacheDirectory() async throws {
        let fixture = try fixture("440Hz.mp3")
        let source = try outputURL("source.mp3")
        let destination = try outputURL("output.m4a")
        let cache = FileManager.default.temporaryDirectory
        try FileManager.default.copyItem(at: fixture, to: source)

        let completed = expectation(description: "conversion completed")
        var terminalState: CompressionState?
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
                terminalState = state
                completed.fulfill()
            case .failed(let error):
                XCTFail("Audio conversion failed: \(error)")
                terminalState = state
                completed.fulfill()
            case .cancelled:
                XCTFail("Audio conversion was cancelled unexpectedly")
                terminalState = state
                completed.fulfill()
            case .started:
                break
            }
        }

        await fulfillment(of: [completed], timeout: 30)
        guard case .completed = terminalState else {
            return XCTFail("Expected successful conversion, got \(String(describing: terminalState))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
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
    }

    func testRepeatedAudioCancellationHasOneTerminalEventAndPreservesSource() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let source = try outputURL("cancellable-source.mov")
        let destination = try outputURL("cancellable-output.m4a")
        try FileManager.default.copyItem(at: fixture, to: source)

        let terminal = expectation(description: "audio cancellation terminal event")
        let recorder = TerminalStateRecorder(terminal)
        let task = await AudioTool.convert(
            source: source,
            destination: destination,
            settings: .init(codec: .aac, bitrate: .value(96_000)),
            overwrite: true,
            deleteSourceFile: true,
            callback: recorder.record
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRepeatedVideoCancellationHasOneTerminalEventAndPreservesSource() async throws {
        let fixture = try fixture("oludeniz.MOV")
        let source = try outputURL("cancellable-video-source.mov")
        let destination = try outputURL("cancellable-video-output.mov")
        try FileManager.default.copyItem(at: fixture, to: source)

        let terminal = expectation(description: "video cancellation terminal event")
        let recorder = TerminalStateRecorder(terminal)
        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: .init(codec: .h264, bitrate: .encoder),
            skipAudio: true,
            overwrite: true,
            deleteSourceFile: true,
            callback: recorder.record
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
