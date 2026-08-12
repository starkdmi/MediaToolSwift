import ImageIO
import XCTest
@testable import MediaToolSwift

final class ImageStabilizationTests: XCTestCase {
    private static let mediaDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("media")

    func testHEICSPrimaryFrameIsPreservedByEncoding() throws {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
            (255, 255, 255),
            (0, 0, 0)
        ]
        var frames = try colors.map { color in
            ImageFrame(cgImage: try makeImage(red: color.0, green: color.1, blue: color.2))
        }
        for index in frames.indices {
            frames[index].unclampedDelayTime = 0.1
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-primary-\(UUID().uuidString).heics")
        defer { try? FileManager.default.removeItem(at: destination) }

        try ImageTool.encode(
            frames,
            at: destination,
            settings: .init(format: .heics),
            primaryIndex: 3
        )

        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(encoded), frames.count)
        XCTAssertEqual(CGImageSourceGetPrimaryImageIndex(encoded), 0)
        let encodedPrimary = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, 0, nil))
        let primaryPixel = try pixel(from: encodedPrimary)
        XCTAssertGreaterThan(primaryPixel.0, 240)
        XCTAssertGreaterThan(primaryPixel.1, 240)
        XCTAssertGreaterThan(primaryPixel.2, 240)
    }

    func testHEICSPrimaryRotationPreservesCyclicVariableTiming() throws {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
            (255, 255, 255),
            (0, 255, 255),
            (0, 0, 0)
        ]
        // ImageIO derives the terminal HEICS sample duration from its preceding
        // timing interval, so make those two cyclic intervals equal while still
        // exercising non-uniform aggregation and primary-first rotation.
        let delays = [0.05, 0.10, 0.15, 0.15, 0.25, 0.30]
        var frames = try colors.enumerated().map { index, color -> ImageFrame in
            var frame = ImageFrame(
                cgImage: try makeImage(red: color.0, green: color.1, blue: color.2)
            )
            frame.unclampedDelayTime = delays[index]
            return frame
        }
        // ImageIO's HEICS writer currently normalizes sequence looping to its
        // supported infinite-loop value. Verify the framework preserves that
        // representable value across primary rotation and frame reduction.
        frames[0].loopCount = 0
        let adjusted = try frames.withAdjustedFrameRate(
            frameRate: 3,
            duration: 1,
            primaryIndex: 3
        )
        let adjustedFrames = try XCTUnwrap(adjusted.frames)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-primary-timing-\(UUID().uuidString).heics")
        defer { try? FileManager.default.removeItem(at: destination) }

        try ImageTool.encode(
            adjustedFrames,
            at: destination,
            settings: .init(format: .heics),
            primaryIndex: adjusted.primaryIndex
        )

        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetPrimaryImageIndex(encoded), 0)
        XCTAssertEqual(CGImageSourceGetCount(encoded), 3)
        XCTAssertEqual(ImageFrame.sequenceLoopCount(from: encoded), 0)

        // The retained source order is [0, 3, 5]. Emitting primary frame 3
        // first must rotate, rather than reorder, that cycle to [3, 5, 0].
        let expectedPixels: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255),
            (0, 0, 0),
            (255, 0, 0)
        ]
        let expectedDelays = [0.40, 0.30, 0.30]
        var encodedDuration = 0.0

        for index in 0 ..< 3 {
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, index, nil))
            let actualPixel = try pixel(from: image)
            XCTAssertEqual(actualPixel.0, expectedPixels[index].0, accuracy: 15)
            XCTAssertEqual(actualPixel.1, expectedPixels[index].1, accuracy: 15)
            XCTAssertEqual(actualPixel.2, expectedPixels[index].2, accuracy: 15)

            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(encoded, index, nil) as? [CFString: Any]
            )
            let heics = try XCTUnwrap(
                properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any]
            )
            let delay = try XCTUnwrap(
                heics[kCGImagePropertyHEICSUnclampedDelayTime] as? Double
                    ?? heics[kCGImagePropertyHEICSDelayTime] as? Double
            )
            XCTAssertEqual(delay, expectedDelays[index], accuracy: 0.01)
            encodedDuration += delay
        }

        XCTAssertEqual(encodedDuration, 1, accuracy: 0.01)

        let decoded = try ImageTool.decode(source: destination)
        XCTAssertEqual(decoded.frames.first?.loopCount, 0)
        XCTAssertTrue(decoded.frames.dropFirst().allSatisfy { $0.loopCount == nil })
    }

    func testGIFSequenceLoopCountRoundTripsFromGlobalProperties() throws {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255)
        ]
        var frames = try colors.map { color -> ImageFrame in
            var frame = ImageFrame(
                cgImage: try makeImage(red: color.0, green: color.1, blue: color.2)
            )
            frame.unclampedDelayTime = 0.1
            return frame
        }
        frames[1].loopCount = 4

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwift-loop-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: destination) }

        try ImageTool.encode(
            frames,
            at: destination,
            settings: .init(format: .gif)
        )

        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(ImageFrame.sequenceLoopCount(from: encoded), 4)

        let decoded = try ImageTool.decode(source: destination)
        XCTAssertEqual(decoded.frames.first?.loopCount, 4)
        XCTAssertTrue(decoded.frames.dropFirst().allSatisfy { $0.loopCount == nil })
    }

    func testFrameReductionKeepsSequenceLoopCountWhenFrameZeroIsDropped() throws {
        var frames = (0 ..< 6).map { index -> ImageFrame in
            var frame = ImageFrame()
            frame.unclampedDelayTime = 1.0 / 6.0
            frame.canvasWidth = Double(index)
            return frame
        }
        frames[0].loopCount = 9

        let adjusted = try frames.withAdjustedFrameRate(
            frameRate: 3,
            duration: 1,
            primaryIndex: 4
        )
        let adjustedFrames = try XCTUnwrap(adjusted.frames)

        // Preserving primary frame four forces source frame zero out of this
        // three-frame budget. Sequence metadata must survive independently.
        XCTAssertEqual(adjustedFrames.compactMap(\.canvasWidth), [3, 4, 5])
        XCTAssertEqual(adjustedFrames.compactMap(\.loopCount), [9])
        XCTAssertEqual(adjusted.primaryIndex, 1)
        XCTAssertEqual(
            adjustedFrames.compactMap(\.unclampedDelayTime).reduce(0, +),
            1,
            accuracy: 0.000_001
        )
    }

    func testInvalidAnimatedTimingReturnsMediaError() {
        var invalidFrames = [ImageFrame(), ImageFrame()]
        invalidFrames[0].unclampedDelayTime = .infinity
        XCTAssertThrowsError(try invalidFrames.validatedDuration()) { error in
            XCTAssertEqual(error as? CompressionError, .failedToReadImage)
        }

        let frames = [ImageFrame(), ImageFrame()]
        XCTAssertThrowsError(
            try frames.withAdjustedFrameRate(
                frameRate: 1,
                duration: .leastNonzeroMagnitude,
                primaryIndex: 0
            )
        ) { error in
            XCTAssertEqual(error as? CompressionError, .failedToReadImage)
        }
    }

    private func makeImage(red: UInt8, green: UInt8, blue: UInt8) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 16,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 16 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(from image: CGImage) throws -> (UInt8, UInt8, UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (bytes[0], bytes[1], bytes[2])
    }
}
