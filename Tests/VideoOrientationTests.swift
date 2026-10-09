import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MediaToolSwift

/// Generates sources carrying each of the eight axis-aligned track transforms
/// and checks the displayed first frame of every output against a corner-color
/// layout derived independently from the transform matrices.
final class VideoOrientationTests: XCTestCase {
    /// Encoded frame size; non-square so transposed layouts are distinguishable.
    private static let encodedSize = CGSize(width: 128, height: 64)

    /// Linear parts (a, b, c, d) of the eight axis-aligned track transforms.
    private static let transforms: [(name: String, a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat)] = [
        ("identity", 1, 0, 0, 1),
        ("flip", 1, 0, 0, -1),
        ("mirror", -1, 0, 0, 1),
        ("upsideDown", -1, 0, 0, -1),
        ("clockwise", 0, 1, -1, 0),
        ("counterClockwise", 0, -1, 1, 0),
        ("transpose", 0, 1, 1, 0),
        ("antiTranspose", 0, -1, -1, 0)
    ]

    func testTrackOrientationForAllTransforms() async throws {
        for transform in Self.transforms {
            let source = try await makeSource(transform)
            defer { try? FileManager.default.removeItem(at: source) }
            let expected = Layout.encoded.applying(transform)

            // The fixture itself must display as the matrix predicts.
            let displayed = try await layout(of: source)
            XCTAssertEqual(displayed, expected, "\(transform.name) source")

            let info = try await VideoTool.getInfo(source: source)
            XCTAssertEqual(info.resolution, expected.size, "\(transform.name) info")

            let maybeTrack = await AVURLAsset(url: source).getFirstTrack(withMediaType: .video)
            let track = try XCTUnwrap(maybeTrack)
            let orientedSize = await track.getNaturalSizeWithOrientation()
            XCTAssertEqual(orientedSize, expected.size, "\(transform.name) oriented size")
        }
    }

    func testConversionPreservesDisplayForAllTransforms() async throws {
        var paths: [(name: String, settings: (CGSize) -> CompressionVideoSettings, scale: CGFloat)] = [
            ("re-encode", { _ in .init(codec: .hevc) }, 1),
            ("image", { _ in .init(codec: .hevc, edit: [.process(.image { image, _, _ in image })]) }, 1),
            ("pixelBuffer", { _ in .init(codec: .hevc, edit: [.process(.pixelBuffer { buffer, _, _, _ in buffer })]) }, 1),
            ("resize", { size in .init(codec: .hevc, size: .scale(size.scaled(0.5))) }, 0.5),
            ("crop", { size in .init(codec: .hevc, edit: [.crop(.init(size: size.scaled(0.75)))]) }, 0.75),
            ("image+crop", { size in
                .init(codec: .hevc, edit: [.crop(.init(size: size.scaled(0.75))), .process(.image { image, _, _ in image })])
            }, 0.75)
        ]
        paths += compositionPaths
        for transform in Self.transforms {
            let source = try await makeSource(transform)
            defer { try? FileManager.default.removeItem(at: source) }
            let expected = Layout.encoded.applying(transform)
            for path in paths {
                let settings = path.settings(expected.size)
                let output = try await convert(source, settings: settings)
                defer { try? FileManager.default.removeItem(at: output.url) }
                var scaled = expected
                scaled.size = expected.size.scaled(path.scale)
                XCTAssertEqual(output.info.resolution, scaled.size, "\(transform.name) \(path.name) info")
                let actual = try await layout(of: output.url)
                XCTAssertEqual(actual, scaled, "\(transform.name) \(path.name)")
            }
        }
    }

    /// The `.image` processor must receive frames in display orientation.
    func testImageProcessorReceivesDisplayOrientation() async throws {
        for transform in Self.transforms {
            let source = try await makeSource(transform)
            defer { try? FileManager.default.removeItem(at: source) }
            let expected = Layout.encoded.applying(transform)
            let received = LockedValue<Layout?>(nil)
            let imageProcessor = VideoFrameProcessor.image { image, context, _ in
                received.withValue { if $0 == nil { $0 = Self.layout(of: image, context: context) } }
                return image
            }
            var processors: [(String, VideoFrameProcessor)] = [("image", imageProcessor)]
            processors += compositionProcessors(received)
            for (name, processor) in processors {
                received.set(nil)
                let output = try await convert(source, settings: .init(codec: .hevc, edit: [.process(processor)]))
                try? FileManager.default.removeItem(at: output.url)
                XCTAssertEqual(received.read(), expected, "\(transform.name) \(name) input")
            }
        }
    }

    /// Rotation is applied first, then flip, then mirror, matching `ImageOperation`.
    func testOperationOrderMatchesImages() async throws {
        let combinations: [(name: String, video: Set<VideoOperation>, image: Set<ImageOperation>, steps: [Step])] = [
            ("clockwise+flip", [.rotate(.clockwise), .flip], [.rotate(.clockwise), .flip], [.clockwise, .flip]),
            ("clockwise+mirror", [.rotate(.clockwise), .mirror], [.rotate(.clockwise), .mirror], [.clockwise, .mirror]),
            ("counterClockwise+flip", [.rotate(.counterClockwise), .flip],
             [.rotate(.counterClockwise), .flip], [.counterClockwise, .flip]),
            ("clockwise+flip+mirror", [.rotate(.clockwise), .flip, .mirror],
             [.rotate(.clockwise), .flip, .mirror], [.clockwise, .flip, .mirror])
        ]

        // Images are the reference for the expected order.
        let image = try makeImage()
        defer { try? FileManager.default.removeItem(at: image) }
        for combination in combinations {
            let expected = Layout.encoded.applying(combination.steps)
            for framework in [ImageFramework.ciImage, .cgImage, .vImage] {
                let destination = temporaryOutput("png")
                defer { try? FileManager.default.removeItem(at: destination) }
                _ = try ImageTool.convert(source: image, destination: destination,
                    settings: .init(format: .png, edit: combination.image, preferredFramework: framework))
                let actual = try Self.layout(of: try cgImage(destination))
                XCTAssertEqual(actual, expected, "image \(combination.name) \(framework)")
            }
        }

        var paths: [(name: String, edit: Set<VideoOperation>)] = [
            ("re-encode", []),
            ("image", [.process(.image { image, _, _ in image })])
        ]
        paths += compositionEdits
        for transform in Self.transforms {
            let source = try await makeSource(transform)
            defer { try? FileManager.default.removeItem(at: source) }
            let displayed = Layout.encoded.applying(transform)
            for combination in combinations {
                let expected = displayed.applying(combination.steps)
                for path in paths {
                    let output = try await convert(source,
                        settings: .init(codec: .hevc, edit: combination.video.union(path.edit)))
                    defer { try? FileManager.default.removeItem(at: output.url) }
                    let actual = try await layout(of: output.url)
                    XCTAssertEqual(actual, expected, "\(transform.name) \(combination.name) \(path.name)")
                }
            }
        }
    }

    // MARK: - Platform-dependent paths

    private var compositionPaths: [(name: String, settings: (CGSize) -> CompressionVideoSettings, scale: CGFloat)] {
        #if os(visionOS)
        return []
        #else
        return [("imageComposition", { _ in
            .init(codec: .hevc, edit: [.process(.imageComposition { image, _, _ in image })])
        }, 1)]
        #endif
    }

    private var compositionEdits: [(name: String, edit: Set<VideoOperation>)] {
        #if os(visionOS)
        return []
        #else
        return [("imageComposition", [.process(.imageComposition { image, _, _ in image })])]
        #endif
    }

    private func compositionProcessors(_ received: LockedValue<Layout?>) -> [(String, VideoFrameProcessor)] {
        #if os(visionOS)
        return []
        #else
        return [("imageComposition", .imageComposition { image, context, _ in
            received.withValue { if $0 == nil { $0 = Self.layout(of: image, context: context) } }
            return image
        })]
        #endif
    }

    // MARK: - Layout model

    /// Quadrant colors of a frame, as displayed (top-left origin).
    fileprivate struct Layout: Equatable, CustomStringConvertible {
        var size: CGSize
        /// Colors in top-left, top-right, bottom-left, bottom-right order.
        var corners: [Color]

        static let encoded = Layout(size: VideoOrientationTests.encodedSize, corners: [.red, .green, .blue, .white])

        var description: String { "\(Int(size.width))x\(Int(size.height)) \(corners)" }

        /// Maps quadrant centers with a linear transform in top-left-origin
        /// coordinates, the convention of `CGAffineTransform` track transforms.
        func applying(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat) -> Layout {
            let positions: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
            var result = corners
            for (index, (x, y)) in positions.enumerated() {
                let mappedX: CGFloat = a * x + c * y
                let mappedY: CGFloat = b * x + d * y
                let target = positions.firstIndex { $0.0 == mappedX && $0.1 == mappedY }!
                result[target] = corners[index]
            }
            let transposes = a == 0
            return Layout(size: transposes ? CGSize(width: size.height, height: size.width) : size, corners: result)
        }

        func applying(_ transform: (name: String, a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat)) -> Layout {
            applying(a: transform.a, b: transform.b, c: transform.c, d: transform.d)
        }

        func applying(_ steps: [Step]) -> Layout {
            steps.reduce(self) { layout, step in
                switch step {
                case .clockwise: return layout.applying(a: 0, b: 1, c: -1, d: 0)
                case .counterClockwise: return layout.applying(a: 0, b: -1, c: 1, d: 0)
                case .flip: return layout.applying(a: 1, b: 0, c: 0, d: -1)
                case .mirror: return layout.applying(a: -1, b: 0, c: 0, d: 1)
                }
            }
        }
    }

    fileprivate enum Step { case clockwise, counterClockwise, flip, mirror }

    fileprivate enum Color: CaseIterable, CustomStringConvertible {
        case red, green, blue, white

        var description: String { String(rgb.0 > 0 ? (rgb.1 > 0 ? "W" : "R") : (rgb.1 > 0 ? "G" : "B")) }

        var rgb: (UInt8, UInt8, UInt8) {
            switch self {
            case .red: return (255, 0, 0)
            case .green: return (0, 255, 0)
            case .blue: return (0, 0, 255)
            case .white: return (255, 255, 255)
            }
        }

        static func nearest(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
            allCases.min { lhs, rhs in
                lhs.distance(r, g, b) < rhs.distance(r, g, b)
            }!
        }

        private func distance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
            let (cr, cg, cb) = rgb
            let dr: Int = Int(cr) - Int(r)
            let dg: Int = Int(cg) - Int(g)
            let db: Int = Int(cb) - Int(b)
            return dr * dr + dg * dg + db * db
        }
    }

    // MARK: - Sampling

    private func layout(of video: URL) async throws -> Layout {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image: CGImage
        if #available(macOS 13, iOS 16, tvOS 16, *) {
            image = try await generator.image(at: .zero).image
        } else {
            image = try generator.copyCGImage(at: .zero, actualTime: nil)
        }
        return try Self.layout(of: image)
    }

    /// Samples quadrant centers of an image in top-left-origin rows.
    private static func layout(of image: CGImage) throws -> Layout {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Bitmap context memory starts with the top row.
        let left: Int = width / 4, right: Int = width * 3 / 4
        let top: Int = height / 4, bottom: Int = height * 3 / 4
        let samples: [(Int, Int)] = [(left, top), (right, top), (left, bottom), (right, bottom)]
        let corners = samples.map { x, y in
            let offset = (y * width + x) * 4
            return Color.nearest(pixels[offset], pixels[offset + 1], pixels[offset + 2])
        }
        return Layout(size: CGSize(width: width, height: height), corners: corners)
    }

    /// Samples a Core Image frame, whose origin is at the bottom left.
    private static func layout(of image: CIImage, context: CIContext) -> Layout? {
        let normalized = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        guard let cgImage = context.createCGImage(normalized, from: normalized.extent) else { return nil }
        return try? layout(of: cgImage)
    }

    // MARK: - Fixtures

    /// Encodes three frames whose stored pixels follow `Layout.encoded`.
    private func makeSource(_ transform: (name: String, a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat)) async throws -> URL {
        let url = temporaryOutput("mov")
        let size = Self.encodedSize
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
        ])
        input.expectsMediaDataInRealTime = false

        // Translate the rotated frame back into the positive quadrant, as
        // camera-authored transforms do.
        var matrix = CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0)
        let bounds = CGRect(origin: .zero, size: size).applying(matrix)
        matrix.tx = -bounds.minX
        matrix.ty = -bounds.minY
        input.transform = matrix

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frame = try makeFrame()
        for index in 0 ..< 3 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    private func makeFrame() throws -> CVPixelBuffer {
        let width = Int(Self.encodedSize.width), height = Int(Self.encodedSize.height)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ] as CFDictionary, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let corner = Layout.encoded.corners[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
                let (r, g, b) = corner.rgb
                let offset = y * rowBytes + x * 4
                base[offset] = b
                base[offset + 1] = g
                base[offset + 2] = r
                base[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    /// Writes `Layout.encoded` as an orientation-free PNG.
    private func makeImage() throws -> URL {
        let frame = try makeFrame()
        let ciImage = CIImage(cvPixelBuffer: frame)
        let cgImage = try XCTUnwrap(CIContext().createCGImage(ciImage, from: ciImage.extent))
        let url = temporaryOutput("png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func cgImage(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func temporaryOutput(_ pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MediaToolOrientation-\(UUID()).\(pathExtension)")
    }

    private func convert(_ source: URL, settings: CompressionVideoSettings) async throws -> (url: URL, info: VideoInfo) {
        let destination = temporaryOutput("mov")
        let info = try await VideoTool.convert(source: source, destination: destination,
            videoSettings: settings, skipAudio: true)
        return (destination, info)
    }
}

private extension CGSize {
    func scaled(_ factor: CGFloat) -> CGSize {
        CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
    }
}
