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

let configs: [ImageInput] = [
    ImageInput(
        filename: "iphone_x.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_iphone_x.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_iphone_x_heif10.heic",
                settings: ImageSettings(format: .heif10),
                result: ImageInfo(format: .heif, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x.HEIC",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_heic.jpg",
                settings: ImageSettings(format: .jpeg, size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "google_pixel_7.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 2495, height: 2865), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_google_pixel_7.jpg",
                settings: ImageSettings(format: .jpeg),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 2495, height: 2865), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "starkdev.png",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_starkdev.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_ci.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .ciImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_cg.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .cgImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_starkdev_vi.jpg",
                settings: ImageSettings(format: .jpeg, preserveAlphaChannel: false, backgroundColor: CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), preferredFramework: .vImage),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "whatsapp.webp",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 958, height: 1280), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_whatsapp.tiff",
                settings: ImageSettings(format: .tiff),
                result: ImageInfo(format: .tiff, size: CGSize(width: 958, height: 1280), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
            ImageConfig(
                filename: "converted_whatsapp.ico",
                settings: ImageSettings(format: .ico, size: .crop(options: .init(size: CGSize(width: 256, height: 256), aligment: .center))),
                result: ImageInfo(format: .ico, size: CGSize(width: 256, height: 256), hasAlpha: false, isHDR: false, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
//    MARK: ANIMATED
    ImageInput(
        filename: "animation.webp",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, framesCount: 21, frameRate: 20, duration: 1.05),
        configs: [
            ImageConfig(
                filename: "converted_animation.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 512, height: 512), hasAlpha: true, isHDR: false, framesCount: 21, frameRate: 20, duration: 1.05)
            ),
        ]
    ),
    ImageInput(
        filename: "animated.gif",
        info: ImageInfo(format: .gif, size: CGSize(width: 640, height: 640), hasAlpha: true, isHDR: false, framesCount: 91, frameRate: 50, duration: 1.02),
        configs: [
            ImageConfig(
                filename: "converted_animated.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 640, height: 640), hasAlpha: true, isHDR: false, framesCount: 91, frameRate: 50, duration: 1.02)
            ),
        ]
    ),
    ImageInput(
        filename: "amazing.gif",
        info: ImageInfo(format: .gif, size: CGSize(width: 300, height: 300), hasAlpha: true, isHDR: false, framesCount: 61, frameRate: 50, duration: 1.22),
        configs: [
            ImageConfig(
                filename: "converted_amazing.heic",
                settings: ImageSettings(format: .heics),
                result: ImageInfo(format: .heics, size: CGSize(width: 300, height: 300), hasAlpha: true, isHDR: false, framesCount: 61, frameRate: 50, duration: 1.22)
            ),
        ]
    ),
    ImageInput(
        filename: "rally_burst.heic",
        info: ImageInfo(format: .heics, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, framesCount: 60, frameRate: 25, duration: 2.4),
        configs: [
            ImageConfig(
                filename: "converted_rally_burst.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, framesCount: 60, frameRate: 25, duration: 2.4)
            ),
        ]
    ),
    ImageInput(
        filename: "bird_burst.heif",
        info: ImageInfo(format: .heics, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, framesCount: 90, frameRate: 30, duration: 3.0),
        configs: [
            ImageConfig(
                filename: "converted_bird_burst.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 640, height: 360), hasAlpha: true, isHDR: false, framesCount: 90, frameRate: 30, duration: 3.0)
            ),
        ]
    ),
    ImageInput(
        filename: "sea_animation.heic",
        info: ImageInfo(format: .heics, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 25, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_sea_animation.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
        ]
    ),
    ImageInput(
        filename: "starfield_animation.heif",
        info: ImageInfo(format: .heics, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 25, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_starfield_animation_vi.gif",
                settings: ImageSettings(format: .gif, preferredFramework: .vImage),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
            ImageConfig(
                filename: "converted_starfield_animation_cg.gif",
                settings: ImageSettings(format: .gif, preferredFramework: .cgImage),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 25, duration: 4.8)
            ),
            ImageConfig(
                filename: "converted_starfield_animation.gif",
                settings: ImageSettings(format: .gif, frameRate: 16),
                result: ImageInfo(format: .gif, size: CGSize(width: 256, height: 144), hasAlpha: true, isHDR: false, framesCount: 76, frameRate: 17, duration: 4.56) // frameRate is 16.67
            ),
        ]
    ),
//    TODO: Invalid frame rate, 12 instead of 13, original 13.33 (!)
    /*ImageInput(
        filename: "bouncing_beach_ball.png",
        info: ImageInfo(format: .png, size: CGSize(width: 100, height: 100), hasAlpha: true, isHDR: false, framesCount: 120, frameRate: 13, duration: 4.8),
        configs: [
            ImageConfig(
                filename: "converted_bouncing_beach_ball.gif",
                settings: ImageSettings(format: .gif),
                result: ImageInfo(format: .gif, size: CGSize(width: 100, height: 100), hasAlpha: true, isHDR: false, framesCount: 20, frameRate: 13, duration: 0.0)
            ),
        ]
    ),*/
//    MARK: HDR
    ImageInput(
        filename: "oludeniz.heic",
        info: ImageInfo(format: .heif10, size: CGSize(width: 1080, height: 1920), hasAlpha: false, isHDR: true, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_oludeniz.tiff",
                settings: ImageSettings(format: .tiff, size: .fit(.hd)),
                result: ImageInfo(format: .tiff, size: CGSize(width: 720, height: 1280), hasAlpha: false, isHDR: true, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
    ImageInput(
        filename: "HDR.heic",
        info: ImageInfo(format: .heif10, size: CGSize(width: 4096, height: 3072), hasAlpha: false, isHDR: true, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_HDR.png",
                settings: ImageSettings(format: .png),
                result: ImageInfo(format: .png, size: CGSize(width: 4096, height: 3072), hasAlpha: false, isHDR: true, framesCount: 1, frameRate: nil, duration: nil)
            ),
        ]
    ),
//    MARK: Oriented
    ImageInput(
        filename: "iphone_x_2.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .upMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_2.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .upMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_3.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .down, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_3.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .down, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_4.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .downMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_4.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .downMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_5.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .leftMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_5.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .leftMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_6.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .right, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_6.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .right, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_7.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .rightMirrored, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_7.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .rightMirrored, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    ),
    ImageInput(
        filename: "iphone_x_8.jpg",
        info: ImageInfo(format: .jpeg, size: CGSize(width: 3024, height: 4032), hasAlpha: false, isHDR: false, orientation: .left, framesCount: 1, frameRate: nil, duration: nil),
        configs: [
            ImageConfig(
                filename: "converted_iphone_x_8.jpg",
                settings: ImageSettings(size: .fit(.hd)),
                result: ImageInfo(format: .jpeg, size: CGSize(width: 960, height: 1280), hasAlpha: false, isHDR: false, orientation: .left, framesCount: 1, frameRate: nil, duration: nil)
            )
        ]
    )
]

class MediaToolImageTests: XCTestCase {
    static let testsDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent()
    static let mediaDirectory = testsDirectory.appendingPathComponent("media")
    static let tempDirectory = mediaDirectory.appendingPathComponent("temp")

    static var setUpCalled = false

    override func setUp() {
        guard !Self.setUpCalled else { return }

        super.setUp()

        var isDirectory: ObjCBool = true
        if !FileManager.default.fileExists(atPath: Self.tempDirectory.path, isDirectory: &isDirectory) {
            try! FileManager.default.createDirectory(atPath: Self.tempDirectory.path, withIntermediateDirectories: false)
        }

        Self.setUpCalled = true
    }

    override func tearDown() {
        // Clean temp files
        /*do {
            let files = try! FileManager.default.contentsOfDirectory(at: Self.tempDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in files where !(
                file.pathExtension.lowercased() == "jpg"   ||
                file.pathExtension.lowercased() == "jpeg"  ||
                file.pathExtension.lowercased() == "png"   ||
                file.pathExtension.lowercased() == "bmp"   ||
                file.pathExtension.lowercased() == "tiff"  ||
                file.pathExtension.lowercased() == "ico"   ||
                file.pathExtension.lowercased() == "gif"   ||
                file.pathExtension.lowercased() == "heic"  ||
                file.pathExtension.lowercased() == "heif"  ||
                file.pathExtension.lowercased() == "heics" ||
                file.pathExtension.lowercased() == "webp"  ||
                file.hasDirectoryPath
            ) {
                try FileManager.default.removeItem(at: file)
            }
        } catch { }*/

        super.tearDown()
    }

    func testHDR() async {
        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.heic")
        let destination = Self.tempDirectory.appendingPathComponent("converted_oludeniz.heic")

        _ = try! ImageTool.convert(
            source: source,
            destination: destination,
            settings: ImageSettings(format: .heif10),
            overwrite: true
        )

        let imageSource = CGImageSourceCreateWithURL(destination as CFURL, nil)!
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let depth = properties![kCGImagePropertyDepth] as? Int
        XCTAssert(depth! > 8 && cgImage.bitsPerComponent > 8, "Not a HDR image")
    }

    func testMetadata() async {
        let source = Self.mediaDirectory.appendingPathComponent("iphone_x.jpg")
        let destination = Self.tempDirectory.appendingPathComponent("metadata_iphone_x.png")

        _ = try! ImageTool.convert(
            source: source,
            destination: destination,
            settings: ImageSettings(format: .png), // .heif10
            overwrite: true
        )

        let imageSource = CGImageSourceCreateWithURL(destination as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let gps = properties![kCGImagePropertyGPSDictionary] as? [CFString: Any]
        XCTAssert(!(gps?.isEmpty ?? true), "No GPS data")
    }

    func testSaveConcurrent() async {
        let source = Self.mediaDirectory.appendingPathComponent("iphone_x.jpg")
        let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil)!
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!

        let concurrentQueue = DispatchQueue(label: "MediaToolSwift.image.concurrent.tests", qos: .userInitiated, attributes: .concurrent)

        let destination1 = Self.tempDirectory.appendingPathComponent("converted_test_iphone_x.png")
        try? FileManager.default.removeItem(at: destination1)
        let expectation1 = XCTestExpectation(description: "Image Test")
        concurrentQueue.async {
            print("#1 started")
            try? ImageTool.saveImage([ImageFrame(cgImage: cgImage)], at: destination1, settings: ImageSettings(format: .png))
            print("#1 finished")
            expectation1.fulfill()
        }

        let destination2 = Self.tempDirectory.appendingPathComponent("converted_test_iphone_x.jpeg")
        try? FileManager.default.removeItem(at: destination2)
        let expectation2 = XCTestExpectation(description: "Image Test 2")
        concurrentQueue.async {
            print("#2 started")
            try? ImageTool.saveImage([ImageFrame(cgImage: cgImage)], at: destination2, settings: ImageSettings(format: .jpeg))
            print("#2 finished")
            expectation2.fulfill()
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 20)
    }

    func testAllImages() async {
        var count = 0
        var expectations: [XCTestExpectation] = []
        let saveQueue = DispatchQueue(label: "MediaToolSwift.image.tests", qos: .userInitiated, attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: 8)
        for file in configs {
            let source = Self.mediaDirectory.appendingPathComponent(file.filename)
            for i in 0 ..< file.configs.count {
                count += 1
                let config = file.configs[i]
                let destination = Self.tempDirectory.appendingPathComponent(config.filename)

                let expectation = XCTestExpectation(description: "Test Images \(destination.path)")
                expectations.append(expectation)
                saveQueue.async {
                    semaphore.wait()
                    print("started \(config.filename)")
                    _ = try! ImageTool.convert(
                        source: source,
                        destination: destination,
                        settings: config.settings,
                        overwrite: true
                    )
                    expectation.fulfill()
                    print("finished \(config.filename)")
                    semaphore.signal()
                }
            }
        }

        await fulfillment(of: expectations, timeout: Double(60 * count))

        for file in configs {
            for i in 0 ..< file.configs.count {
                let config = file.configs[i]
                let settings = config.result
                let destination = Self.tempDirectory.appendingPathComponent(config.filename)

                // Exists
                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "File not found")
    
                let imageSource = CGImageSourceCreateWithURL(destination as CFURL, nil)!
                let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
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
                var format: ImageFormat?
                if let utType = cgImage.utType, let utTypeFormat = ImageFormat(utType) {
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
                XCTAssertEqual(hasAlpha, settings.hasAlpha, "No Alpha channel found in \(config.filename)")

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
