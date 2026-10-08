import AVFoundation
import XCTest
@testable import MediaToolSwift

/// A video track that yields no samples must fail the conversion instead of
/// completing into a file without a video track.
final class VideoEmptyReadTests: XCTestCase {
    private var outputDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwiftEmptyReadTests-\(UUID().uuidString)", isDirectory: true)
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

    func testCutWithoutVideoSamplesFails() async throws {
        let directory = try XCTUnwrap(outputDirectory)
        let source = directory.appendingPathComponent("source.mov")
        let destination = directory.appendingPathComponent("output.mov")
        // The reader completes without a single decoded frame for a range past
        // the end of the video track, as it did for decodes failing on CI. A
        // video composition renders frames for such a range, so only the track
        // output path can be driven here.
        try await Self.writeSource(to: source)

        do {
            let info = try await VideoTool.convert(
                source: source,
                destination: destination,
                videoSettings: .init(codec: .h264, edit: [.cut(from: 1.0, to: 1.5)]),
                // Audio samples let the writer finish, as the CI conversions did
                copyExtendedFileMetadata: false
            )
            XCTFail("Conversion without video samples succeeded: \(info)")
        } catch {
            XCTAssertEqual(error as? CompressionError, .failedToReadVideo, "\(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "Failed conversion left an output file")
    }

    /// Writes 1/3 second of 64x64 H.264 video next to 2 seconds of silent AAC
    private static func writeSource(to url: URL) async throws {
        let size = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        writer.add(audioInput)
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)

        for frame in 0 ..< 10 {
            try await Self.waitUntilReady(videoInput)
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(frame * 20), CVPixelBufferGetBytesPerRow(buffer) * size)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        videoInput.markAsFinished()

        var description = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ), noErr)
        let format = try XCTUnwrap(formatDescription)

        let framesPerChunk = 4_410
        for chunk in 0 ..< 20 {
            try await Self.waitUntilReady(audioInput)
            var blockBuffer: CMBlockBuffer?
            XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: nil,
                blockLength: framesPerChunk * 2,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: framesPerChunk * 2,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &blockBuffer
            ), noErr)
            let block = try XCTUnwrap(blockBuffer)
            XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: framesPerChunk * 2), noErr)
            var sampleBuffer: CMSampleBuffer?
            XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil,
                dataBuffer: block,
                formatDescription: format,
                sampleCount: framesPerChunk,
                presentationTimeStamp: CMTime(value: CMTimeValue(chunk * framesPerChunk), timescale: 44_100),
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            ), noErr)
            XCTAssertTrue(audioInput.append(try XCTUnwrap(sampleBuffer)))
        }
        audioInput.markAsFinished()

        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }

    /// Polls readiness with a deadline; the inputs are filled one after the
    /// other, so writer interleaving could otherwise stall the loop forever.
    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !input.isReadyForMoreMediaData {
            guard Date() < deadline else {
                throw CompressionError(description: "Writer input for \(input.mediaType.rawValue) did not become ready")
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
