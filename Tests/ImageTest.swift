// swiftlint:disable force_try force_cast
#if canImport(MediaToolSwift)
@testable import MediaToolSwift
import XCTest
import Foundation
import AVFoundation
import Accelerate.vImage
import UniformTypeIdentifiers
#if os(macOS)
import ImageIO
import AppKit
#else
import UIKit
#endif

struct ImageConfig {
    let filename: String
    let settings: ImageSettings
    let result: ImageInfo
}

struct ImageInput {
    let filename: String
    let info: ImageInfo
    let configs: [ImageConfig]
}

private func allImageConfigs() -> [ImageInput] {
    return [
    ImageInput(
        filename: "iphone_x.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_iphone_x.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_iphone_x_heif10.heic",
                settings: ImageSettings(format: .heif10),
                result: ImageInfo(format: .heif, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x.HEIC",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_heic.jpg",
                settings: ImageSettings(format: .jpeg, size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "google_pixel_7.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 2495, height: 2865), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_google_pixel_7.jpg",
                settings: ImageSettings(format: .jpeg),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 2495, height: 2865), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "starkdev.png",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_starkdev.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_ci.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .ciImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_cg.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .cgImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_vi.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .vImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "whatsapp.webp",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 958, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_whatsapp.tiff",
                settings: ImageSettings(format: .tiff),
                result: ImageInfo(format: .tiff, size: CGSize(width: 958, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_whatsapp.ico",
                settings: ImageSettings(format: .ico, size: .crop(options: .init(size: CGSize(width: 256, height: 256), aligment: .center))),
                result: ImageInfo(format: .ico, size: CGSize(width: 256, height: 256), hasAlpha: false, isHDR: false, bitDepth: 8, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
//    MARK: ANIMATED
    ImageInput(
        filename: "animation.webp",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 21, frameRate: 20, duration: 1.05),
        configs: [
            ImageConfig(
                filename: "converted_animation.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 21, frameRate: 20, duration: 1.05)
            ),
        ]
    ),
    ImageInput(
        filename: "animated.gif",
        info: ImageInfo(format: .gif, size: CGSize(width: 640, height: 640), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 91, frameRate: 50, duration: 1.02),
        configs: [
            ImageConfig(
                filename: "converted_animated.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 640, height: 640), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 91, frameRate: 50, duration: 1.02)
            ),
        ]
    ),
    ImageInput(
        filename: "amazing.gif",
        info: ImageInfo(format: .gif, size: CGSize(width: 300, height: 300), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 61, frameRate: 50, duration: 1.22),
        configs: [
            ImageConfig(
                filename: "converted_amazing.heic",
                settings: ImageSettings(format: .heics),
                result: ImageInfo(format: .heics, size: CGSize(width: 300, height: 300), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 61, frameRate: 50, duration: 1.22)
            ),
        ]
    ),
    ImageInput(
        filename: "rally_burst.heic",
        info: ImageInfo(format: .heics, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 60, frameRate: 25, duration: 2.4),
        configs: [
            ImageConfig(
                filename: "converted_rally_burst.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 60, frameRate: 25, duration: 2.4)
            ),
        ]
    ),
    ImageInput(
        filename: "bird_burst.heif",
        info: ImageInfo(format: .heics, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 90, frameRate: 30, duration: 3.0),
        configs: [
            ImageConfig(
                filename: "converted_bird_burst.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 90, frameRate: 30, duration: 3.0)
            ),
        ]
    ),
    ImageInput(
        filename: "sea_animation.heic",
        info: ImageInfo(format: .heics, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 25, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_sea_animation.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
        ]
    ),
    ImageInput(
        filename: "starfield_animation.heif",
        info: ImageInfo(format: .heics, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 25, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_starfield_animation_vi.gif",
                settings: ImageSettings(format: .gif, preferredFramework: .vImage),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
            ImageConfig(
                filename: "converted_starfield_animation_cg.gif",
                settings: ImageSettings(format: .gif, preferredFramework: .cgImage),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
            ImageConfig(
                filename: "converted_starfield_animation.gif",
                settings: ImageSettings(format: .gif, frameRate: 16),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 76, frameRate: 16, duration: 4.8)
            ),
        ]
    ),
//    TODO: Invalid frame rate, 12 instead of 13, original 13.33 (!)
    /*ImageInput(
        filename: "bouncing_beach_ball.png",
        info: ImageInfo(format: .png, size: CGSize(width: 100, height: 100), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 120, frameRate: 13, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_bouncing_beach_ball.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 100, height: 100), hasAlpha: true, isHDR: false, bitDepth: 8, framesCount: 20, frameRate: 13, duration: 0.0)
            ),
        ]
    ),*/
//    MARK: HDR
    ImageInput(
        filename: "oludeniz.heic",
        info: ImageInfo(format: .heif10, size: CGSize(width: 1080, height: 1920), hasAlpha: false, isHDR: true, bitDepth: 10, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_oludeniz.tiff",
                settings: ImageSettings(format: .tiff, size: .fit(.hd)),
                result: ImageInfo(format: .tiff, size: CGSize(width: 720, height: 1280), hasAlpha: false, isHDR: true, bitDepth: 10, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "HDR.heic",
        info: ImageInfo(format: .heif10, size: CGSize(width: 4096, height: 3072), hasAlpha: false, isHDR: true, bitDepth: 10, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_HDR.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 4096, height: 3072), hasAlpha: false, isHDR: true, bitDepth: 10, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
//    MARK: Oriented
    ImageInput(
        filename: "iphone_x_2.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .upMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_2.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .upMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_3.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .down, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_3.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .down, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_4.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .downMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_4.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .downMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_5.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .leftMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_5.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .leftMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_6.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .right, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_6.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .right, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_7.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .rightMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_7.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .rightMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_8.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .left, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_8.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, bitDepth: 8, orientation: .left, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    )
    ]
}

private let extendedMediaTestsEnabled = ProcessInfo.processInfo.environment["MEDIATOOLSWIFT_EXTENDED_MEDIA"] == "1"
private let smokeImageFixtures: Set<String> = [
    "iphone_x.jpg",
    "iphone_x.HEIC",
    "starkdev.png",
    "whatsapp.webp",
    "amazing.gif",
    "oludeniz.heic"
]

private func imageConfigurations() -> [ImageInput] {
    let allConfigs = allImageConfigs()
    return extendedMediaTestsEnabled
        ? allConfigs
        : allConfigs.filter { smokeImageFixtures.contains($0.filename) }
}

class MediaToolImageTests: XCTestCase {
    static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let mediaDirectory = testsDirectory.appendingPathComponent("media")

    private var outputDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaToolSwiftImageTests-\(UUID().uuidString)", isDirectory: true)
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

    private func containsTransparentPixels(in image: CGImage) throws -> Bool {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: bytesPerPixel).contains {
            pixels[$0] < UInt8.max
        }
    }

    /// Whether plain ImageIO can write the frames of `source` as a HEICS
    /// sequence on this machine.
    ///
    /// HEICS output goes through the platform HEVC encoder, which is absent on
    /// some virtualized hosts. Probing with `CGImageDestination` alone keeps an
    /// environment that cannot encode the sequence at all separable from a
    /// regression in this library, which still fails the test because the probe
    /// succeeds wherever the encoder works.
    private func imageIOCanEncodeHEICSSequence(from source: URL) throws -> Bool {
        let url = try outputURL("heics-probe-\(UUID().uuidString).heics")
        defer { try? FileManager.default.removeItem(at: url) }

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let count = CGImageSourceGetCount(imageSource)
        let utType = try XCTUnwrap(ImageFormat.heics.utType)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, utType, count, nil))

        for index in 0 ..< count {
            guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyHEICSDictionary: [
                    kCGImagePropertyHEICSDelayTime: 0.1,
                    kCGImagePropertyHEICSUnclampedDelayTime: 0.1
                ]
            ] as CFDictionary)
        }

        return CGImageDestinationFinalize(destination)
    }

    private static func encodeFixture(source: URL, destination: URL, format: ImageFormat) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw CompressionError.failedToReadImage
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CompressionError.failedToReadImage
        }

        try ImageTool.encode([ImageFrame(cgImage: cgImage)], at: destination, settings: .init(format: format))
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw CompressionError.failedToSaveImage
        }
        return destination
    }

    func testOpenEXRCompatibility() throws {
        let openEXRIdentifier = "com.ilm.openexr-image"

        XCTAssertTrue(ImageFormat.allCases.contains(.exr))
        XCTAssertEqual(ImageFormat.exr.utType as String?, openEXRIdentifier)
        XCTAssertEqual(ImageFormat(openEXRIdentifier as CFString), .exr)
        XCTAssertEqual(ImageFormat("exr"), .exr)

        let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard destinationTypes.contains(openEXRIdentifier) else {
            throw XCTSkip("ImageIO does not provide OpenEXR encoding on this platform")
        }

        let source = try fixture("starkdev.png")
        let destination = try outputURL("compatibility.exr")
        _ = try Self.encodeFixture(source: source, destination: destination, format: .exr)

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, openEXRIdentifier)
    }

    func testHDR() async throws {
        let source = try fixture("oludeniz.heic")
        let destination = try outputURL("converted_oludeniz.heic")

        _ = try ImageTool.convert(
            source: source,
            destination: destination,
            settings: ImageSettings(format: .heif10),
            overwrite: true
        )

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let depth = try XCTUnwrap(properties[kCGImagePropertyDepth] as? Int)
        XCTAssert(depth > 8 && cgImage.bitsPerComponent > 8, "Not a HDR image")
    }

    func testMetadata() async throws {
        let source = try fixture("iphone_x.jpg")
        let destination = try outputURL("metadata_iphone_x.png")

        _ = try ImageTool.convert(
            source: source,
            destination: destination,
            settings: ImageSettings(format: .png), // .heif10
            overwrite: true
        )

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        XCTAssertFalse(gps.isEmpty, "No GPS data")
    }

    func testSaveConcurrent() async throws {
        let source = try fixture("iphone_x.jpg")
        let destinations = [
            try outputURL("converted_test_iphone_x.png"),
            try outputURL("converted_test_iphone_x.jpeg")
        ]
        let formats: [ImageFormat] = [.png, .jpeg]

        let outputs = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
            for (destination, format) in zip(destinations, formats) {
                group.addTask {
                    try Self.encodeFixture(source: source, destination: destination, format: format)
                }
            }

            var results: [URL] = []
            for try await output in group {
                results.append(output)
            }
            return results
        }

        XCTAssertEqual(outputs.count, destinations.count)
        for output in outputs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "File not found: \(output.lastPathComponent)")
            XCTAssertNotNil(CGImageSourceCreateWithURL(output as CFURL, nil), "Could not read \(output.lastPathComponent)")
        }
    }

    func testAllImages() throws {
        let configs = imageConfigurations()

        // Outputs that were skipped or failed to convert, which the
        // verification pass below has nothing to inspect for. A conversion
        // failure names the config that produced it and lets the remaining
        // configurations run, so one test run reports every broken conversion
        // instead of only the first.
        var unwrittenOutputs: Set<String> = []
        for file in configs {
            let source = try fixture(file.filename)
            for config in file.configs {
                if config.settings.format == .heics, try !imageIOCanEncodeHEICSSequence(from: source) {
                    unwrittenOutputs.insert(config.filename)
                    print("Skipped \(config.filename): this platform cannot encode \(file.filename) as a HEICS sequence")
                    continue
                }

                let destination = try outputURL(config.filename)
                do {
                    _ = try ImageTool.convert(
                        source: source,
                        destination: destination,
                        settings: config.settings,
                        overwrite: true
                    )
                } catch {
                    unwrittenOutputs.insert(config.filename)
                    XCTFail("Conversion of \(file.filename) to \(config.filename) failed: \(error)")
                }
            }
        }

        for file in configs {
            for config in file.configs where !unwrittenOutputs.contains(config.filename) {
                let settings = config.result
                let destination = try outputURL(config.filename)

                // Exists
                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "File not found")

                let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
                let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
                let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]

                // Orientation
                if let orientation = settings.orientation, let orientationProperty = imageProperties?[kCGImagePropertyOrientation] as? UInt32 {
                    let current = CGImagePropertyOrientation(rawValue: orientationProperty)
                    XCTAssertEqual(current, orientation, "Invalid orientation at \(config.filename)")
                }

                // HDR
                let depth = imageProperties?[kCGImagePropertyDepth] as? Int ?? 8
                let isHDR = depth > 8 || cgImage.bitsPerComponent > 8
                XCTAssertEqual(isHDR, settings.isHDR, "No HDR data found in \(config.filename)")

                // Image format
                // The container type is authoritative: an ICO wraps a PNG
                // payload, for which `CGImage.utType` reports `public.png`.
                var format: ImageFormat?
                if let sourceType = CGImageSourceGetType(imageSource),
                   let sourceFormat = ImageFormat(sourceType) {
                    format = sourceFormat
                } else if let utType = cgImage.utType, let utTypeFormat = ImageFormat(utType) {
                    format = utTypeFormat
                } else if let pathFormat = ImageFormat(destination.pathExtension) {
                    format = pathFormat
                }
                if format == .heif, isHDR {
                    format = .heif10
                }
                XCTAssertEqual(format, settings.format, "Invalid format for \(config.filename)")

                // Alpha
                let alpha = imageProperties?[kCGImagePropertyHasAlpha] as? Bool ?? false
                let hasAlpha = alpha || cgImage.hasAlpha
                // ImageIO on iOS 26 and tvOS 26 keeps an alpha channel in PNG
                // output even for a fully opaque source, so channel presence no
                // longer proves the channel carries data. Assert transparency
                // instead of storage when no alpha is expected.
                if settings.hasAlpha {
                    XCTAssertTrue(hasAlpha, "No alpha channel found in \(config.filename)")
                } else if hasAlpha {
                    XCTAssertFalse(
                        try containsTransparentPixels(in: cgImage),
                        "Unexpected transparent pixels in \(config.filename)"
                    )
                }

                // Size
                var orientation: CGImagePropertyOrientation?
                if let orientationProperty = imageProperties?[kCGImagePropertyOrientation] as? UInt32 {
                    orientation = CGImagePropertyOrientation(rawValue: orientationProperty)
                }
                let size = cgImage.size(orientation: orientation)
                XCTAssertEqual(size, settings.size, "Invalid size at \(config.filename)")

                // Frames amount
                let totalFrames = CGImageSourceGetCount(imageSource)
                XCTAssertEqual(totalFrames, settings.framesCount, "Invalid frames amount at \(config.filename)")

                // Frame rate & duration for animated images
                if totalFrames > 1 {
                    var duration: Double = 0.0
                    for index in 0 ..< totalFrames {
                        var delayTime: Double?
                        var unclampedDelayTime: Double?
                        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] {
                            if let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                                delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
                                unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime]  as? Double
                            } else if let heicsProperties = properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any] {
                                delayTime = heicsProperties[kCGImagePropertyHEICSDelayTime] as? Double
                                unclampedDelayTime = heicsProperties[kCGImagePropertyHEICSUnclampedDelayTime]  as? Double
                            } else if #available(macOS 11, iOS 14, tvOS 14, *), let webPProperties = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
                                delayTime = webPProperties[kCGImagePropertyWebPDelayTime] as? Double
                                unclampedDelayTime = webPProperties[kCGImagePropertyWebPUnclampedDelayTime]  as? Double
                            } else if let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
                                delayTime = pngProperties[kCGImagePropertyAPNGDelayTime] as? Double
                                unclampedDelayTime = pngProperties[kCGImagePropertyAPNGUnclampedDelayTime]  as? Double
                            }
                        }
                        duration += unclampedDelayTime ?? delayTime ?? 0.0
                    }
                    let nominalFrameRate = Int((Double(totalFrames) / duration).rounded())
                    XCTAssertEqual(nominalFrameRate, settings.frameRate, "Invalid frame rate at \(config.filename)")
                }
            }
        }
    }
}
#endif
