// swiftlint:disable force_try force_cast
#if canImport(MediaToolSwift) // && !os(visionOS)
@testable import MediaToolSwift
import XCTest
import Foundation
import AVFoundation
import VideoToolbox
import CoreVideo
import Vision
import Accelerate.vImage
import UniformTypeIdentifiers
import QuartzCore
#if os(macOS)
import ImageIO
import AppKit
#else
import UIKit
#endif

struct ConfigList {
    let filename: String
    let url: String? // [nil] for local file
    let input: Parameters
    let configs: [Config]
}

struct Config {
    let videoSettings: CompressionVideoSettings
    let output: Parameters
}

struct Parameters {
    let filename: String
    let filesize: Int?
    let resolution: CGSize?
    let videoCodec: AVVideoCodecType
    let fileType: VideoFileType
    let bitrate: Int? // in bits (!), approximate, [nil] to skip, [-1] to check if output is less than input
    let frameRate: Int? // [nil] to skip, [-1] to check if output is less than input
    let duration: Double? // in seconds
    let hasAlpha: Bool?
}

struct AudioData {
    let format: AudioFormatID
    let bitrate: Int?
    let sampleRate: Int?
    let channels: Int?
}

// Configurations used by tests
var configurations: [ConfigList] {
    var videos = [
        // Big Buck Bunny H.264 - https://test-videos.co.uk/bigbuckbunny/mp4-h264
        ConfigList(
            filename: "bigbuckbunny_h264_640x360.mp4",
            url: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4",
            input: Parameters(
                filename: "bigbuckbunny_h264_640x360.mp4",
                filesize: 991_017,
                resolution: CGSize(width: 640.0, height: 360.0),
                videoCodec: .h264,
                fileType: .mp4,
                bitrate: 789_000,
                frameRate: 30,
                duration: 10.0,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevc
                    ),
                    output: Parameters(
                        filename: "exported_bigbuckbunny_h264_640x360.mp4",
                        filesize: -1,
                        resolution: CGSize(width: 640.0, height: 360.0),
                        videoCodec: .hevc,
                        fileType: .mp4,
                        bitrate: -1,
                        frameRate: 30,
                        duration: 10.0,
                        hasAlpha: false
                    )
                )
            ]
        ),
        ConfigList(
            filename: "bigbuckbunny_h264_1280x720.mp4",
            url: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_2MB.mp4",
            input: Parameters(
                filename: "bigbuckbunny_h264_1280x720.mp4",
                filesize: 1_978_137,
                resolution: CGSize(width: 1280.0, height: 720.0),
                videoCodec: .h264,
                fileType: .mp4,
                bitrate: 1_579_000,
                frameRate: 30,
                duration: 10.0,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevc,
                        size: .fit(CGSize(width: 720.0, height: 720.0))
                    ),
                    output: Parameters(
                        filename: "exported_bigbuckbunny_h264_1280x720.mp4",
                        filesize: -1,
                        resolution: CGSize(width: 720.0, height: 404.0), // 404 rounded from 405
                        videoCodec: .hevc,
                        fileType: .mp4,
                        bitrate: -1,
                        frameRate: 30,
                        duration: 10.0,
                        hasAlpha: false
                    )
                )
            ]
        ),

        ConfigList(
            filename: "chromecast.mp4",
            url: nil,
            input: Parameters(
                filename: "chromecast.mp4",
                filesize: 2_498_125,
                resolution: CGSize(width: 1280.0, height: 720.0),
                videoCodec: .h264,
                fileType: .mp4,
                bitrate: 1_135_000,
                frameRate: 24, // 23.98
                duration: 15.02,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevc
                    ),
                    output: Parameters(
                        filename: "exported_chromecast.mp4",
                        filesize: 2_100_000,
                        resolution: CGSize(width: 1280.0, height: 720.0),
                        videoCodec: .hevc,
                        fileType: .mp4,
                        bitrate: 950_000,
                        frameRate: 24, // 23.98
                        duration: 15.02,
                        hasAlpha: false
                    )
                )
            ]
        ),

        // Portrait Video H.264
        ConfigList(
            filename: "sunset_h264_portrait_480_848.mp4",
            url: nil,
            input: Parameters(
                filename: "sunset_h264_portrait_480_848.mp4",
                filesize: 1_066_855,
                resolution: CGSize(width: 480.0, height: 848.0),
                videoCodec: .h264,
                fileType: .mp4,
                bitrate: 1_639_000,
                frameRate: 30,
                duration: 5.2,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevcWithAlpha, // should be replaced with hevc by compressor
                        preserveAlphaChannel: false
                    ),
                    output: Parameters(
                        filename: "exported_sunset_h264_portrait_480_848.mp4",
                        filesize: nil,
                        resolution: CGSize(width: 480.0, height: 848.0),
                        videoCodec: .hevc,
                        fileType: .mp4,
                        bitrate: nil,
                        frameRate: 30,
                        duration: 5.2,
                        hasAlpha: false
                    )
                )
            ]
        ),

        // Alpha channel
        ConfigList(
            filename: "transparent_ball_hevc.mov",
            url: nil,
            input: Parameters(
                filename: "transparent_ball_hevc.mov",
                filesize: 236_047,
                resolution: CGSize(width: 1280.0, height: 720.0),
                videoCodec: .hevcWithAlpha,
                fileType: .mov,
                bitrate: 462_000,
                frameRate: 60,
                duration: 4.0,
                hasAlpha: true
            ),
            configs: [
                // Preserve alpha channel
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevcWithAlpha,
                        bitrate: .value(450_000),
                        preserveAlphaChannel: true
                    ),
                    output: Parameters(
                        filename: "exported_transparent_ball_hevc.mov",
                        filesize: nil,
                        resolution: CGSize(width: 1280.0, height: 720.0),
                        videoCodec: .hevcWithAlpha,
                        fileType: .mov,
                        bitrate: nil,
                        frameRate: 60,
                        duration: 4.0,
                        hasAlpha: true
                    )
                ),
                // Remove alpha channel
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevc,
                        preserveAlphaChannel: false
                    ),
                    output: Parameters(
                        filename: "exported_transparent_ball_hevc_2.mov",
                        filesize: nil,
                        resolution: CGSize(width: 1280.0, height: 720.0),
                        videoCodec: .hevc,
                        fileType: .mov,
                        bitrate: nil,
                        frameRate: 60,
                        duration: 4.0,
                        hasAlpha: false
                    )
                )
            ]
        ),

        // HDR, portrait (Google Pixel 7)
        ConfigList(
            filename: "google_pixel_hdr.mp4",
            url: nil,
            input: Parameters(
                filename: "google_pixel_hdr.mp4",
                filesize: 43_376_890,
                resolution: CGSize(width: 2160.0, height: 3840.0),
                videoCodec: .hevc,
                fileType: .mp4,
                bitrate: 43_299_000,
                frameRate: 30, // 29.99
                duration: 7.97,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(bitrate: .value(4_000_000)),
                    output: Parameters(
                        filename: "exported_google_pixel_hdr.mov",
                        filesize: nil, // ~= 17_000_000
                        resolution: CGSize(width: 2160.0, height: 3840.0),
                        videoCodec: .hevcWithAlpha,
                        fileType: .mov,
                        bitrate: nil, // ~- 15_715_000
                        frameRate: 30,
                        duration: 7.97,
                        hasAlpha: false
                    )
                )
            ]
        ),

        // Slo-mo, 120/240fps, all video codecs supported, lowering frame rate (240->120), custom bitrate and video operations works
        // On iOS any videos above ~120 fps handled as slo-mo
        ConfigList(
            filename: "slomo_120_fps.mov",
            url: nil,
            input: Parameters(
                filename: "slomo_120_fps.mov",
                filesize: 13_354_827,
                resolution: CGSize(width: 1080.0, height: 1920.0),
                videoCodec: .hevc,
                fileType: .mov,
                bitrate: 21_273_000,
                frameRate: 108, // originally 120, but was cropped so at average is lower
                duration: 4.33,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(bitrate: .value(21_000_000)),
                    output: Parameters(
                        filename: "exported_slomo_120_fps.mov",
                        filesize: nil, // ~= 13_303_814
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .hevc,
                        fileType: .mov,
                        bitrate: 21_000_000, // nil
                        frameRate: 120,
                        duration: 4.33,
                        hasAlpha: false
                    )
                )
            ]
        ),
        ConfigList(
            filename: "slomo_240_fps.mov",
            url: nil,
            input: Parameters(
                filename: "slomo_240_fps.mov",
                filesize: 31_071_646,
                resolution: CGSize(width: 1080.0, height: 1920.0),
                videoCodec: .hevc,
                fileType: .mov,
                bitrate: 53_915_000,
                frameRate: 240,
                duration: 4.60,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(bitrate: .value(10_000_000)),
                    output: Parameters(
                        filename: "exported_slomo_240_fps.mov",
                        filesize: nil, // ~= 31_030_000
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .hevc,
                        fileType: .mov,
                        bitrate: nil, // ~- 53_915_000
                        frameRate: 240,
                        duration: 4.60,
                        hasAlpha: false
                    )
                ),
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .h264,
                        bitrate: .value(10_000_000),
                        frameRate: 120
                    ),
                    output: Parameters(
                        filename: "exported_slomo_240_fps_2.mov",
                        filesize: nil, // ~= 5_908_000
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .h264,
                        fileType: .mov,
                        bitrate: 10_000_000, // nil
                        frameRate: 120,
                        duration: 4.60,
                        hasAlpha: false
                    )
                )
            ]
        ),

        // Time-lapse, normally stored at 30 fps as any other video
        ConfigList(
            filename: "time_lapse.MOV",
            url: nil,
            input: Parameters(
                filename: "time_lapse.MOV",
                filesize: 3_340_362,
                resolution: CGSize(width: 1080.0, height: 1920.0),
                videoCodec: .hevc,
                fileType: .mov,
                bitrate: 14_565_000,
                frameRate: 30,
                duration: 1.83,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(codec: .h264),
                    output: Parameters(
                        filename: "exported_time_lapse.mov",
                        filesize: nil, // ~= 1_560_000
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .h264,
                        fileType: .mov,
                        bitrate: nil, // 6_800_000
                        frameRate: 30,
                        duration: 1.83,
                        hasAlpha: false
                    )
                )
            ]
        )
    ]

    // Prores
    #if !os(visionOS)
    videos.append(contentsOf: [
        ConfigList(
            filename: "transparent_ball_prores.mov",
            url: nil,
            input: Parameters(
                filename: "transparent_ball_prores.mov",
                filesize: 236_047,
                resolution: CGSize(width: 1280.0, height: 720.0),
                videoCodec: .proRes4444,
                fileType: .mov,
                bitrate: 20_723_000,
                frameRate: 60,
                duration: 4.0,
                hasAlpha: true
            ),
            configs: [
                // Prores output
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .proRes4444,
                        size: .fit(CGSize(width: 720.0, height: 405.0)),
                        preserveAlphaChannel: true
                    ),
                    output: Parameters(
                        filename: "exported_transparent_ball_prores.mov",
                        filesize: nil,
                        resolution: CGSize(width: 720.0, height: 405),
                        videoCodec: .proRes4444,
                        fileType: .mov,
                        bitrate: nil,
                        frameRate: 60,
                        duration: 4.0,
                        hasAlpha: true
                    )
                ),
                // HEVC output
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .hevcWithAlpha,
                        preserveAlphaChannel: true
                    ),
                    output: Parameters(
                        filename: "exported_transparent_ball_prores_2.mov",
                        filesize: nil,
                        resolution: CGSize(width: 1280.0, height: 720.0),
                        videoCodec: .hevcWithAlpha,
                        fileType: .mov,
                        bitrate: nil,
                        frameRate: 60,
                        duration: 4.0,
                        hasAlpha: true
                    )
                )
            ]
        ),

        // HDR, Portrait
        ConfigList(
            filename: "oludeniz.MOV",
            url: nil,
            input: Parameters(
                filename: "oludeniz.MOV",
                filesize: 8_429_475,
                resolution: CGSize(width: 1080.0, height: 1920.0),
                videoCodec: .hevc,
                fileType: .mov,
                bitrate: 8_688_000,
                frameRate: 30,
                duration: 7.6,
                hasAlpha: false
            ),
            configs: [
                Config(
                    videoSettings: CompressionVideoSettings(bitrate: .value(4_000_000)),
                    output: Parameters(
                        filename: "exported_oludeniz_default.mov",
                        filesize: nil, // ~= 3_875_000
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .hevc,
                        fileType: .mov,
                        bitrate: nil, // ~- 4_000_000
                        frameRate: 30,
                        duration: 7.6,
                        hasAlpha: false
                    )
                ),
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .proRes4444,
                        bitrate: .encoder,
                        size: .fit(CGSize(width: 3000.0, height: 4000.0)),
                        frameRate: 60
                    ),
                    output: Parameters(
                        filename: "exported_oludeniz_prores.mov",
                        filesize: nil,
                        resolution: CGSize(width: 1080.0, height: 1920.0),
                        videoCodec: .proRes4444,
                        fileType: .mov,
                        bitrate: nil,
                        frameRate: 30,
                        duration: 7.6,
                        hasAlpha: false
                    )
                ),
                Config(
                    videoSettings: CompressionVideoSettings(
                        size: .fit(CGSize(width: 1280.0, height: 1280.0))
                    ),
                    output: Parameters(
                        filename: "exported_oludeniz.mov",
                        filesize: -1, // ~= 1.8 MB
                        resolution: CGSize(width: 720.0, height: 1280.0),
                        videoCodec: .hevc,
                        fileType: .mov,
                        bitrate: -1, // ~= 1.75-2.0 MBps
                        frameRate: 30,
                        duration: 7.6,
                        hasAlpha: false
                    )
                ),
                Config(
                    videoSettings: CompressionVideoSettings(
                        codec: .h264,
                        bitrate: .value(2_000_000),
                        size: .fit(CGSize(width: 720.0, height: 720.0)),
                        frameRate: 24
                    ),
                    output: Parameters(
                        filename: "exported_oludeniz.mp4",
                        filesize: 2_050_000,
                        resolution: CGSize(width: 404.0, height: 720.0), // floor applied to value of 405 by encoder
                        videoCodec: .h264,
                        fileType: .mp4,
                        bitrate: 2_000_000,
                        frameRate: 24,
                        duration: 7.6,
                        hasAlpha: false
                    )
                )
            ]
        )
    ])
    #endif

    // INFO: VP9 and AV1 are not supported yet
    // Big Buck Bunny VP9 - https://test-videos.co.uk/bigbuckbunny/webm-vp9
    // Big Buck Bunny AV1 - https://test-videos.co.uk/bigbuckbunny/webm-av1

    // Jellyfish - https://test-videos.co.uk/jellyfish/mp4-h265
    // Chromium test videos - https://github.com/chromium/chromium/tree/master/media/test/data
    // WebM test videos - https://github.com/webmproject/libwebm/tree/main/testing/testdata
    return []
}

// Download file from url and save to local directory 
func downloadFile(url: String, path: String) async throws {
    let url: URL = URL(string: url)!
    let (data, _) = try await URLSession.shared.data(from: url)
    try data.write(to: URL(fileURLWithPath: path))
}

class MediaToolSwiftTests: XCTestCase {

    static let testsDirectory = URL(fileURLWithPath: #file).deletingLastPathComponent()
    static let mediaDirectory = testsDirectory.appendingPathComponent("media")
    static let tempDirectory = mediaDirectory.appendingPathComponent("temp")

    static var setUpCalled = false

    override func setUp() {
        guard !Self.setUpCalled else { return }

        // Used to stop execution of fulfillment expectations whenever at least one of them fails
        // XCTestObservationCenter.shared.addTestObserver(TestObserver())

        super.setUp()

        Task {
            // Fetch all video files
            for config in configurations {
                if let url = config.url {
                    let path: String = Self.mediaDirectory.appendingPathComponent(config.filename).path
                    if !FileManager.default.fileExists(atPath: path) {
                        try! await downloadFile(url: url, path: path)
                    }
                }
            }
        }

        var isDirectory: ObjCBool = true
        if !FileManager.default.fileExists(atPath: Self.tempDirectory.path, isDirectory: &isDirectory) {
            try! FileManager.default.createDirectory(atPath: Self.tempDirectory.path, withIntermediateDirectories: false)
        }

        Self.setUpCalled = true
    }

    override func tearDown() {
        // Delete system AVAssetWriter temp files
        do {
            let files = try! FileManager.default.contentsOfDirectory(at: Self.tempDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in files where !(
                file.pathExtension.lowercased() == "mov"   ||
                file.pathExtension.lowercased() == "mp4"   ||
                file.pathExtension.lowercased() == "m4v"   ||
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
                file.pathExtension.lowercased() == "m4a"  ||
                file.pathExtension.lowercased() == "mp3"  ||
                file.pathExtension.lowercased() == "wav"  ||
                file.pathExtension.lowercased() == "caf"  ||
                file.pathExtension.lowercased() == "aiff"  ||
                file.pathExtension.lowercased() == "aifc"  ||
                file.hasDirectoryPath
            ) {
                try FileManager.default.removeItem(at: file)
            }
        } catch { }

        super.tearDown()
    }

    static func fulfill(_ expectation: XCTestExpectation) {
        // Allow compressor to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Let the app to finish
            expectation.fulfill()
        }
    }

    #if targetEnvironment(simulator)
    // Apple TV and iOS simulator compression is really slow
    let osAdditionalTimeout: TimeInterval = 300 // 5 min
    #else
    let osAdditionalTimeout: TimeInterval = 0
    #endif

    #if os(macOS)
    func testImageThumbnails() async {
        let expectation = XCTestExpectation(description: "Test Video Image Thumbnails")
        let source = Self.mediaDirectory.appendingPathComponent("chromecast.mp4")
        let asset = AVAsset(url: source)
        
        var thumbnails: [VideoThumbnail] = []
        try! VideoTool.thumbnailImages(for: asset, at: [4.1], size: CGSize(width: 256, height: 256)) { items in
            thumbnails.append(contentsOf: items)
            Self.fulfill(expectation)
        }

        await fulfillment(of: [expectation], timeout: 10 + osAdditionalTimeout)

        XCTAssertTrue(!thumbnails.isEmpty, "Empty thumbnails array")
    }
    #endif

    #if os(macOS)
    func testFileThumbnails() async {
        let expectation = XCTestExpectation(description: "Test Video File Thumbnails")
        let thumbnailsDirectory = Self.tempDirectory.appendingPathComponent("thumbnails")
        // Create directory if non exists
        var isDirectory: ObjCBool = true
        if !FileManager.default.fileExists(atPath: thumbnailsDirectory.path, isDirectory: &isDirectory) {
            try! FileManager.default.createDirectory(atPath: thumbnailsDirectory.path, withIntermediateDirectories: false)
        }

        let source = Self.mediaDirectory.appendingPathComponent("chromecast.mp4")
        let destination = thumbnailsDirectory.appendingPathComponent("chromecast_thumb.jpg")
        let asset = AVAsset(url: source)
        
        var error: Error?
        VideoTool.thumbnailFiles(of: asset, at: [VideoThumbnailRequest(time: 1.0, url: destination), VideoThumbnailRequest(time: 4.1, url: destination), VideoThumbnailRequest(time: 7.5, url: destination)], settings: ImageSettings(format: .jpeg), completion: { result in
            switch result {
            case .failure(let err):
                error = err
            case .success(_):
                break
            }
            Self.fulfill(expectation)
        })

        await fulfillment(of: [expectation], timeout: 10 + osAdditionalTimeout)

        XCTAssertNil(error, error!.localizedDescription)

        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
    }
    #endif

    #if os(macOS)
    func testThumbnail() async {
        let expectation = XCTestExpectation(description: "Test Video Thumbnails")
        let thumbnailsDirectory = Self.tempDirectory.appendingPathComponent("thumbnails")
        // Create directory if non exists
        var isDirectory: ObjCBool = true
        if !FileManager.default.fileExists(atPath: thumbnailsDirectory.path, isDirectory: &isDirectory) {
            try! FileManager.default.createDirectory(atPath: thumbnailsDirectory.path, withIntermediateDirectories: false)
        }

        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV") // chromecast.mp4 transparent_ball_hevc.mov oludeniz.MOV
        let asset = AVAsset(url: source)

        let formats: [ImageFormat: String] = [
            .heif: ".heic",
            .heic: ".c.heic",
            .heif10: ".10.heic",
            .png: ".png",
            .jpeg: ".jpg",
            .jpeg2000: ".jpeg",
            .gif: ".gif",
            .tiff: ".tiff",
            .bmp: ".bmp",
            .ico: ".ico"
        ]

        for (format, ext) in formats {
            let imageUrl = thumbnailsDirectory.appendingPathComponent("thumb\(ext)")
            if FileManager.default.fileExists(atPath: imageUrl.path) {
                try! FileManager.default.removeItem(atPath: imageUrl.path)
            }

            let settings = ImageSettings(
                format: format,
                //size: .fit(.hd),
                //size: .crop(fit: .hd, options: .init(size: CGSize(width: 512, height: 512), aligment: .center)),
                size: .crop(options: .init(size: CGSize(width: 256, height: 256), aligment: .center)),
                edit: [
                    //.rotate(.angle(.pi/4))
                    //.rotate(.angle(.pi/4), fill: .color(alpha: 255, red: 255, green: 255, blue: 255)),
                    //.rotate(.clockwise)
                    /*.imageProcessing { image in
                     // This will extend the image frame by a little (!)
                     image.applyingFilter("CIGaussianBlur", parameters: [
                     "inputRadius": 7.5
                     ])
                     }*/
                ]
            )

            VideoTool.thumbnailFiles(of: asset, at: [.init(time: 4.1, url: imageUrl)], settings: settings, timeToleranceBefore: .zero, timeToleranceAfter: .zero, completion: { result in
                switch result {
                case .success(_):
                    break
                case .failure(let error):
                    print(error)
                }
                Self.fulfill(expectation)
            })
        }

        await fulfillment(of: [expectation], timeout: 30 + osAdditionalTimeout)

        // Check files exists
        for (_, ext) in formats {
            let imageUrl = thumbnailsDirectory.appendingPathComponent("thumb\(ext)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: imageUrl.path))
        }

        // Check the HDR data persist
        let heic10URL = thumbnailsDirectory.appendingPathComponent("thumb.10.heic")
        let heicImageSource = CGImageSourceCreateWithURL(heic10URL as CFURL, nil)!
        let heicCGImage = CGImageSourceCreateImageAtIndex(heicImageSource, 0, nil)!
        XCTAssertTrue(heicCGImage.bitsPerComponent > 8, "No HDR data found")
        let heicProperties = CGImageSourceCopyPropertiesAtIndex(heicImageSource, 0, nil) as? [CFString: Any]
        XCTAssertTrue(heicProperties?[kCGImagePropertyDepth] as? Int ?? 8 > 8, "No HDR data found (depth)")

        // Delete thumbnails
        /*do {
            let files = try! FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
        } catch { }*/
    }
    #endif

    #if !os(visionOS)
    /// Video overlay, apply CIFilters, and many more using custom CIImage processor
    func testImageProcessing() async {
        #if os(macOS)
        typealias Font = NSFont
        typealias Color = NSColor
        #else
        typealias Font = UIFont
        typealias Color = UIColor
        #endif

        let expectation = XCTestExpectation(description: "Image Processing Example")
        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")
        let destination = Self.tempDirectory.appendingPathComponent("image_processor_oludeniz.MOV")

        let duration = AVAsset(url: source).duration.seconds // source video duration, be carefull with cutting

        let white = CGColor(red: 244/255, green: 244/255, blue: 244/255, alpha: 1.0)
        //let dark = CGColor(red: 43/255, green: 43/255, blue: 43/255, alpha: 1.0)
        //let black = CGColor(red: 35/255, green: 34/255, blue: 35/255, alpha: 1.0)
        let darkGreen = CGColor(red: 7/255, green: 94/255, blue: 84/255, alpha: 1.0)
        //let orange = CGColor(red: 252/255, green: 176/255, blue: 69/255, alpha: 0.9)
        let yellow = CGColor(red: 250/255, green: 197/255, blue: 22/255, alpha: 1.0)
        //let red = CGColor(red: 250/255, green: 75/255, blue: 22/255, alpha: 1.0)

        let imageProcessor = { (_ image: CIImage, _ context: CIContext, _ time: Double) -> CIImage in
            /* Parameters:
             - Image: An CIImage to modify
             - Context: CIContext for reuse
             - Time: Frame time in seconds, use this to show/hide overlays or filter based on video time
           */
            var image = image
            let size = image.extent.size

            // Warning: This method called once for each frame, the code in this block must be optimized
            // For example initialize filter once and reuse, render text to image once, then composite based on time

            // Warning: When .mirror, .flip or other tranformation (except rotation) is applied to video, it's also applied overlays
            // To prevent apply oposite tranformation
            let mirrored = CGAffineTransform(scaleX: -1.0, y: 1.0).translatedBy(x: -size.width, y: 0)
            // let flipped = CGAffineTransform(scaleX: 1.0, y: -1.0).translatedBy(x: 0, y: -size.height)
            let transform: CGAffineTransform = mirrored // .identity, mirrored, flipped

            // Apply Blur after 2.8 sec
            if time >= 2.8 {
                //https://developer.apple.com/documentation/coreimage/processing_an_image_using_built-in_filters
                //https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci
                image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    "inputRadius": 7.5
                 ]).cropped(to: CGRect(origin: .zero, size: size))
            }

            // Progress
            let timeFactor = time/duration
            let timeFactorBefore = { (end: Double) in time / end }
            let timeFactorAfter = { (start: Double) in max(0, (time - start) / (duration - start)) }
            let timeFactorRange = { (start: Double, end: Double) in
                let progress = (time - start) / (end - start)
                return max(0, min(progress, 1))
            }

            // Overlay text, all the duration
            let shadow = NSShadow()
            shadow.shadowColor = Color.white
            shadow.shadowBlurRadius = Easing.default(from: -5, to: 15, with: timeFactor)
            // Text attributes
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Font.systemFont(ofSize: Easing.default(from: 92, to: 200, with: timeFactor)),
                .foregroundColor: time <= 6 ?
                    Easing.linear.interpolate(from: white, to: yellow, with: timeFactorBefore(6)) :
                    Easing.sineIn.interpolate(from: yellow, to: darkGreen, with: timeFactorAfter(6)),
                .backgroundColor: CGColor(red: 40/255, green: 40/255, blue: 40/255, alpha: Easing.default(from: 0.5, to: 0.0, with: timeFactorBefore(2.8))),
                .strokeWidth: time >= 2.8 ? Easing.default(from: 3, to: 2, with: timeFactor) : 0.0,
                 .shadow: shadow
            ]

            let attributedString = NSAttributedString(string: " Ölüdeniz 🏖️  ", attributes: attributes)
            let textFilter = CIFilter(name: "CIAttributedTextImageGenerator", parameters: [
                "inputText": attributedString
            ])!
            var textImage = textFilter.outputImage!

            // Center text
            textImage = textImage.transformed(by: .init(
                translationX: Easing.bounceOut.interpolate(
                    from: (size.width - textImage.extent.width) / 2.0 + 200,
                    to: (size.width - textImage.extent.width) / 2.0,
                    with: timeFactor
                ),
                y: Easing.bounceOut.interpolate(
                    from: (size.height - textImage.extent.height) / 2.0 + 640,
                    to: (size.height - textImage.extent.height) / 2.0,
                    with: timeFactor
                )
            ))
            // Transform
            textImage = textImage.transformed(by: transform)

            // Place text over source image
            image = textImage
                .cropped(to: image.extent)
                .composited(over: image)

            // Advanced String/Letters Animation by rendering each letter separately and then animate position/opacity/atd.
            if timeFactor < 0.99 {
                #if os(macOS)
                let fontSize: CGFloat = 36
                #else
                let fontSize: CGFloat = 24
                #endif
                let orange = Color(red: 252/255, green: 176/255, blue: 69/255, alpha: 0.9)
                let green = Color(red: 7/255, green: 94/255, blue: 84/255, alpha: 1.0)

                // String to animate with base character attributes
                let storage = NSTextStorage(string: "Animated String ✨", attributes: [
                    .foregroundColor: Color.white,
                    .font: Font.boldSystemFont(ofSize: fontSize),
                    //.kern: 18.0,
                ])

                // Separate attributed strings for each character using .byComposedCharacterSequences
                // Or animate by words, sentences, lines, paragraphs, atd. using .byWords, .byLines, ...
                var attributedCharacters: [NSAttributedString] = []
                storage.string.enumerateSubstrings(in: storage.string.startIndex..<storage.string.endIndex, options: .byComposedCharacterSequences, { (substring, substringRange, _, _) in
                    let range = NSRange(substringRange, in: storage.string)
                    let char = storage.attributedSubstring(from: range)
                    let customized: NSMutableAttributedString = char.mutableCopy() as! NSMutableAttributedString
                    if range.length == 1 {
                        customized.addAttribute(.foregroundColor, value: attributedCharacters.count % 2 == 0 ? orange : green, range: NSMakeRange(0, 1))
                    }
                    attributedCharacters.append(customized)
                })

                // Text size
                let textSize = storage.boundingRect(with: CGRect.infinite.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
    
                // Position on image
                #if os(macOS)
                let spacing: CGFloat = 24 // space between characters
                #else
                let spacing: CGFloat = 32
                #endif
                let allSpacing = max(0, (CGFloat(attributedCharacters.count) - 2)) * spacing
                let centerX = (size.width - (textSize.width + allSpacing)) / 2.0
                // let centerY = (size.height - textSize.height) / 2.0
                let point = CGPoint(x: centerX, y: 256) // starting point
                var offsetX: CGFloat = 0 // used to draw letters one by one while increasing offset

                let stepsY: CGFloat = 10 // animation height - fullSize.height * stepsY
                let startPoint = CGPoint(x: point.x, y: point.y + textSize.height * stepsY)
                let endPoint = CGPoint(x: point.x, y: point.y )

                let delay = 0.3 // delay in animation between chars, from left to right, in sec

                for idx in 0...attributedCharacters.count-1 {
                    let char = attributedCharacters[idx]
                    let size = char.size()
                    let progress = timeFactorRange(Double(idx) * delay, 0.99 * duration)
  
                    // Create an character image
                    #if os(macOS)
                    let characterImage = NSImage(size: size)
                    characterImage.lockFocus()
                    char.draw(at: .zero)
                    characterImage.unlockFocus()
                    // Construct CIImage
                    var ciImage = CIImage(data: characterImage.tiffRepresentation!)!
                    // var ciImage = CIImage(cgImage: characterImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                    #else
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let characterImage = renderer.image { context in
                        char.draw(at: .zero)
                    }
                    var ciImage = CIImage(image: characterImage)!
                    #endif

                     // Position
                    let start = CGPoint(x: startPoint.x + offsetX, y: startPoint.y)
                    let end = CGPoint(x: endPoint.x + offsetX, y: endPoint.y)
                    ciImage = ciImage.transformed(by: .init(
                        translationX: Easing.bounceInOut.interpolate(from: start.x, to: end.x, with: progress),
                        y: Easing.bounceInOut.interpolate(from: start.y, to: end.y, with: progress)
                    ))
                    // Opacity
                    let alpha = Easing.default(from: 0.0, to: 1.0, with: progress)
                    ciImage = ciImage.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(values: [0.0, 0.0, 0.0, CGFloat(alpha)], count: 4),
                    ])

                    offsetX += size.width + spacing

                    // Transform & Insert
                    ciImage = ciImage.transformed(by: transform)

                    image = ciImage
                        .cropped(to: image.extent)
                        .composited(over: image)
                }
            }

            // Image overlay
            if time >= 2.8 {
                let imageUrl = Self.mediaDirectory.appendingPathComponent("starkdev.png")
                var ciImageOverlay = CIImage(contentsOf: imageUrl)! // 512x512
                // Resize
                ciImageOverlay = ciImageOverlay.transformed(by: .init(scaleX: 0.25, y: 0.25))
                // Adjust position
                ciImageOverlay = ciImageOverlay.transformed(by: .init(translationX: size.width - ciImageOverlay.extent.size.width - 44, y: 44))
                // Tint PNG
                ciImageOverlay = CIImage(color: CIColor(red: 244/255, green: 244/255, blue: 244/255, alpha: 1.0))
                    .cropped(to: ciImageOverlay.extent)
                    .applyingFilter("CIBlendWithAlphaMask", parameters: [
                        "inputBackgroundImage": ciImageOverlay,
                        "inputMaskImage": ciImageOverlay
                    ])
                // Time based opacity animation
                let alpha = 1.0 - timeFactorAfter(2.8)
                ciImageOverlay = ciImageOverlay.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(values: [0.0, 0.0, 0.0, CGFloat(alpha)], count: 4),
                ])
                // Transform
                ciImageOverlay = ciImageOverlay.transformed(by: transform)
                // Stack image over source
                image = ciImageOverlay.composited(over: image)
            }

            // Sepia at the end
            if timeFactor >= 0.99 {
                image = image.applyingFilter("CISepiaTone", parameters: [
                    "inputIntensity": 0.8
                ])
            }

            return image
        }

        // var tempPixelBuffer: CVPixelBuffer?
        func dispose() {
            // tempPixelBuffer = nil
        }
        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            fileType: .mov,
             videoSettings: .init(
                codec: .hevc,
                bitrate: .encoder,
                size: .fit(CGSize(width: 720, height: 720)),
                // size: .fit(CGSize(width: 1080, height: 1080)),
                // size: .scale(CGSize(width: 2160, height: 3240)),
                // size: .dynamic { size in .scale(CGSize(width: size.width / 2, height: size.height / 2)) },
                // profile: .hevcMain10,
                // color: .itu2020_hlg,
                edit: [
                    .crop(.init(size: CGSize(width: 1080, height: 1080), aligment: .center)),
                    // .crop(.init(size: CGSize(width: 1080, height: 1620), aligment: .center)),
                    
                    // .process(.imageComposition(imageProcessor)),
                    .process(.image(imageProcessor)),

                    /*.process(.pixelBuffer { pixelBuffer, pixelBufferPool, context, time in
                        autoreleasepool {
                            // Load image
                            let image = CIImage(cvPixelBuffer: pixelBuffer)

                            // Apply Gaussian blur
                            let blurred = image
                                .clampedToExtent()
                                .applyingFilter("CIGaussianBlur", parameters: [
                                    "inputRadius": 7.5
                                ])
                                .cropped(to: image.extent)

                            // Create empty pixel buffer
                            if tempPixelBuffer == nil {
                                /*let status = CVPixelBufferCreate(
                                    kCFAllocatorDefault,
                                    Int(blurred.extent.size.width),
                                    Int(blurred.extent.size.height),
                                    kCVPixelFormatType_32BGRA,
                                    nil,
                                    &tempPixelBuffer
                                )*/
                                let status = CVPixelBufferPoolCreatePixelBuffer(
                                    kCFAllocatorDefault,
                                    pixelBufferPool,
                                    &tempPixelBuffer
                                )
                                guard status == kCVReturnSuccess else { return pixelBuffer }
                            }

                            // Rendrer image to new pixel buffer
                            context.render(blurred, to: tempPixelBuffer!, bounds: blurred.extent, colorSpace: image.colorSpace)
                            context.clearCaches()

                            return tempPixelBuffer!
                        }
                    })*/

                    // .process(.imageComposition { image, _, _ in image }), .mirror,
                    // .process(.pixelBuffer { buffer, _, _, _ in buffer }),
                    // .process(.sampleBuffer { buffer in buffer })
                    //.cut(from: 0.5, to: 7.5)
                    //.rotate(.clockwise), .rotate(.angle(.pi))
                    .mirror,
                ]
            ),
            skipAudio: true,
            overwrite: true,
            callback: { state in
                switch state {
                case .completed, .cancelled:
                    dispose()
                    Self.fulfill(expectation)
                case .failed(let error):
                    dispose()
                    XCTFail(error.localizedDescription)
                default:
                    break
                }
        })

        await fulfillment(of: [expectation], timeout: 30 + osAdditionalTimeout)
    }
    #endif

    func testVideos() async {
        var expectations: [XCTestExpectation] = []

        for file in configurations {
            let source = Self.mediaDirectory.appendingPathComponent(file.filename)

            #if targetEnvironment(simulator) && !os(visionOS)
            // ProRes is not available in simulators
            /*ProRes Decoding & Encoding:
                MacBook Air M2
                MacBook Pro M1 Pro, Max, M2
                iPhone 13 Pro, Pro Max
                iPhone 14 Pro, Pro Max
                iPad Pro (12.9-inch, 5th generation)
                iPad Pro (11-inch, 3rd generation)
                iPad Air (5th generation)

            ProRes Decoding (Bionic A15+):
                iPhone 13, Mini, Pro, Pro Max
                iPhone 14, Plus
                iPhone SE (3rd generation)
                iPad Mini (6th generation)
                Apple TV 4K
            */
            if file.input.videoCodec == .proRes4444 {
                continue
            }
            #endif

            #if os(tvOS)
            // Apple TV doesn't support HEVC with alpha channel decoding
            if file.input.videoCodec == .hevcWithAlpha {
                continue
            }
            #endif

            for config in file.configs {
                let destination = Self.tempDirectory.appendingPathComponent(config.output.filename)
                let expectation = XCTestExpectation(description: "Video processing")

                #if targetEnvironment(simulator) && !os(visionOS)
                if config.videoSettings.codec == .proRes4444 {
                    continue
                }
                #endif

                _ = await VideoTool.convert(
                    source: source,
                    destination: destination,
                    fileType: config.output.fileType,
                    videoSettings: config.videoSettings,
                    audioSettings: nil,
                    overwrite: true,
                    callback: { state in
                        switch state {
                        case .completed, .cancelled:
                            Self.fulfill(expectation)
                        case .failed(let error):
                            XCTFail("\(error.localizedDescription) while compressing \(file.filename)->\(config.output.filename)")
                        default:
                            break
                        }
                })
                expectations.append(expectation)
            }
        }

        await fulfillment(of: expectations, timeout: 30 + osAdditionalTimeout * Double(expectations.count))

        for file in configurations {
            #if targetEnvironment(simulator) && !os(visionOS)
            if file.input.videoCodec == .proRes4444 {
                continue
            }
            #endif

            #if os(tvOS)
            if file.input.videoCodec == .hevcWithAlpha {
                continue
            }
            #endif

            for config in file.configs {
                // Test results
                // 1. video
                // 2. file size
                // 3. resolution
                // 4. bitrate
                // 5. frame rate
                // 6? duration in seconds
                // 7? has alpha channel

                #if targetEnvironment(simulator) && !os(visionOS)
                if config.videoSettings.codec == .proRes4444 {
                    continue
                }
                #endif

                let destination = Self.tempDirectory.appendingPathComponent(config.output.filename)

                // Init video asset
                let asset = AVAsset(url: destination)
                guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
                    XCTFail("No video track found in resulting file (\(config.output.filename))")
                    continue
                }
                let videoDesc = videoTrack.formatDescriptions.first as! CMFormatDescription

                // 1. Video codec
                #if os(OSX)
                let mediaSubType = CMFormatDescriptionGetMediaSubType(videoDesc)
                let mediaSubTypeString = NSFileTypeForHFSTypeCode(mediaSubType)
                // #else
                // let formatName = videoDesc.extensions[.formatName]!.propertyListRepresentation as! String
                // #endif
                if config.output.videoCodec == AVVideoCodecType.hevcWithAlpha {
                    // Fix for HEVC with alpha (AVVideoCodecType.hevcWithAlpha is 'muxa' not 'hvc1')
                    XCTAssertEqual(mediaSubTypeString, "'hvc1'", "\(config.output.filename)")
                } else {
                    XCTAssertEqual(mediaSubTypeString, "'\(config.output.videoCodec.rawValue)'", "\(config.output.filename)")
                }
                #endif

                // 2. File size
                let fileSize = try! FileManager.default.attributesOfItem(atPath: destination.path)[FileAttributeKey.size] as! UInt64
                if let size = config.output.filesize {
                    if size >= 0 {
                        // should equal the value +- 5%
                        let precision = Int(Float(size) * 0.05)
                        XCTAssert(fileSize > UInt64(size - precision) && fileSize < UInt64(size + precision))
                    } else if size < 0, let original = file.input.filesize {
                        // should be less than input
                        XCTAssertLessThanOrEqual(fileSize, UInt64(original),
                                                 "File size should be smaller than input for \(file.filename)->\(config.output.filename)")
                    }
                }

                // 3. Resolution
                if let resolution = config.output.resolution {
                    let videoSize = videoTrack.naturalSizeWithOrientation
                    XCTAssertTrue(
                        videoSize.almostEqual(to: resolution),
                        "Output resolution is incorrect (\(videoSize)) should be (\(resolution))"
                    )
                }

                // 4. Bitrate 
                let estimatedDataRate = videoTrack.estimatedDataRate
                if let bitrate = config.output.bitrate {
                    if bitrate >= 0 {
                        // should equal the value +- 7.5%
                        let precision = Float(bitrate) * 0.075
                        XCTAssert(
                            estimatedDataRate > Float(bitrate) - precision && estimatedDataRate < Float(bitrate) + precision,
                            "Bitrate doesn't match for \(file.filename)->\(config.output.filename). Actual bitrate is \(estimatedDataRate) but should be \(bitrate)"
                        )
                    } else if bitrate < 0 {
                        // should be less than input
                        XCTAssertLessThanOrEqual(estimatedDataRate, Float(file.input.bitrate ?? 0), "\(config.output.filename)")
                    }
                }

                // 5. Frame rate | FPS
                let frameRate = videoTrack.nominalFrameRate.rounded()
                if config.output.frameRate == nil {
                    // should be less then input
                    XCTAssertLessThanOrEqual(frameRate, Float(file.input.frameRate ?? 0), "\(config.output.filename)")
                } else {
                    // equals the value
                    XCTAssertLessThanOrEqual(frameRate, Float(config.output.frameRate ?? 0), "\(config.output.filename)")
                }

                // 6. Duration
                if let duration = config.output.duration {
                    XCTAssert(abs(asset.duration.seconds - duration) < 0.1, "\(config.output.filename)")
                }

                // 7. Alpha channel presence
                if let hasAlpha = config.output.hasAlpha {
                    let hasAlphaChannel = videoDesc.hasAlphaChannel
                    XCTAssertEqual(hasAlphaChannel, hasAlpha, "\(config.output.filename)")
                }
            }
        }
    }

    func testMetadata() async {
        var expectations: [XCTestExpectation] = []

        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")

        let metadataItem = AVMutableMetadataItem()
        metadataItem.key = AVMetadataKey.commonKeyTitle as NSString
        metadataItem.keySpace = AVMetadataKeySpace.common
        metadataItem.value = "Custom Title" as NSString
        metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String

        let customMetadata: [AVMetadataItem] = [metadataItem]

        // Add custom metadata, check existing for correctness
        let destinationOne = Self.tempDirectory.appendingPathComponent("exported_oludeniz_metadata.mov")
        let expectationOne = XCTestExpectation(description: "Compression & metadata")
        expectations.append(expectationOne)
        _ = await VideoTool.convert(
            source: source,
            destination: destinationOne,
            skipAudio: true,
            customMetadata: customMetadata,
            overwrite: true,
            callback: { state in
                switch state {
                case .completed, .cancelled:
                    Task {
                        let asset = AVAsset(url: destinationOne)

                        // Timed metadata track exists
                        let metadataTrack = await asset.getFirstTrack(withMediaType: .metadata)
                        XCTAssert(metadataTrack != nil)

                        // Container metadata
                        let metadata = await asset.getMetadata()
                        XCTAssertEqual(metadata.count, 7)
                        for data in metadata {
                            let key = data.key as! String
                            let value = data.value as! String
                            if key == "com.apple.quicktime.model" {
                                XCTAssertEqual(value, "iPhone 13")
                            } else if key == "com.apple.quicktime.displayname" {
                                XCTAssertEqual(value, "Custom Title")
                            }
                        }

                        // Check file extended attributes for existence and correctness
                        let dictionary = try! FileManager.default.attributesOfItem(atPath: destinationOne.path)
                        let attributes = NSDictionary(dictionary: dictionary)
                        if let extendedAttributes = attributes["NSFileExtendedAttributes"] as? [String: Any] {
                            // XCTAssertEqual(extendedAttributes.count, 4)

                            let whereFromData = extendedAttributes["com.apple.metadata:kMDItemWhereFroms"] as? Data
                            XCTAssert(whereFromData != nil)
                            let whereFrom = try! PropertyListSerialization.propertyList(
                                from: whereFromData!, options: [], format: nil
                            ) as? [String]
                            XCTAssertEqual(whereFrom!.first, "Dmitry Starkov") // "Dmitry S"
                            XCTAssertEqual(whereFrom!.last, "iPhone X") // "iPhone 13"

                            let customLocationData = extendedAttributes["com.apple.assetsd.customLocation"] as? Data
                            XCTAssert(customLocationData != nil)

                            let originalFilenameData = extendedAttributes["com.apple.assetsd.originalFilename"] as? Data
                            XCTAssert(originalFilenameData != nil)
                            let originalFilename = String(data: originalFilenameData!, encoding: .utf8)
                            XCTAssertEqual(originalFilename, "IMG_3754.MOV")
                        }

                        Self.fulfill(expectationOne)
                    }
                case .failed(let error):
                    XCTFail(error.localizedDescription)
                default:
                    break
            }
        })

        // Test no metadata saved
        let destinationTwo = Self.tempDirectory.appendingPathComponent("exported_oludeniz_no_metadata.mov")
        let expectationTwo = XCTestExpectation(description: "Compression & no metadata")
        expectations.append(expectationTwo)
        _ = await VideoTool.convert(
            source: source,
            destination: destinationTwo,
            skipAudio: true,
            skipSourceMetadata: true,
            copyExtendedFileMetadata: false,
            overwrite: true,
            callback: { state in
                switch state {
                case .completed, .cancelled:
                    Task {
                        let asset = AVAsset(url: destinationTwo)

                        // Check timed metadata track obsence
                        let metadataTrack = await asset.getFirstTrack(withMediaType: .metadata)
                        XCTAssertEqual(metadataTrack, nil)

                        // Empty container metadata
                        let metadata = await asset.getMetadata()
                        XCTAssertEqual(metadata.count, 0)

                        // Check extended attributes obsence
                        let dictionary = try! FileManager.default.attributesOfItem(atPath: destinationTwo.path)
                        let attributes = NSDictionary(dictionary: dictionary)
                        if let extendedAttributes = attributes["NSFileExtendedAttributes"] as? [String: Any] {
                            // XCTAssertEqual(extendedAttributes.count, 1)
                            let whereFromData = extendedAttributes["com.apple.metadata:kMDItemWhereFroms"] as? Data
                            XCTAssertEqual(whereFromData, nil)
                            let customLocationData = extendedAttributes["com.apple.assetsd.customLocation"] as? Data
                            XCTAssertEqual(customLocationData, nil)
                            let originalFilenameData = extendedAttributes["com.apple.assetsd.originalFilename"] as? Data
                            XCTAssertEqual(originalFilenameData, nil)
                        }

                        Self.fulfill(expectationTwo)
                    }
                case .failed(let error):
                    XCTFail(error.localizedDescription)
                default:
                    break
            }
        })

        await fulfillment(of: expectations, timeout: 20 + osAdditionalTimeout)
    }

    func testCancellation() async {
        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")

        let destination = Self.tempDirectory.appendingPathComponent("exported_oludeniz_cancel.mov")
        let expectation = XCTestExpectation(description: "Compression & cancellation")
        var status: CompressionState?
        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: CompressionVideoSettings(
                codec: .h264,
                bitrate: .encoder
            ),
            skipAudio: true,
            overwrite: true,
            deleteSourceFile: false,
            callback: { state in
                status = state
                switch state {
                case .completed, .cancelled:
                    Self.fulfill(expectation)
                case .failed(let error):
                    XCTFail(error.localizedDescription)
                default:
                    break
                }
        })

        // Cancel
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            task.cancel()
        }

        await fulfillment(of: [expectation], timeout: 20)

        // Check the state
        XCTAssertEqual(status, .cancelled)

        // Check no files created 
        let exists = FileManager.default.fileExists(atPath: destination.path)
        XCTAssertEqual(exists, false)
    }

    func testFileOptions() async {
        var expectations: [XCTestExpectation] = []

        // Copy file
        let sourceOne = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")
        let destinationOne = Self.tempDirectory.appendingPathComponent("exported_oludeniz_overwrite.mov")
        try? FileManager.default.copyItem(at: sourceOne, to: destinationOne)
        // Should fail if exists
        let expectationOne = XCTestExpectation(description: "Compression & overwrite")
        expectations.append(expectationOne)
        _ = await VideoTool.convert(
            source: sourceOne,
            destination: destinationOne,
            overwrite: false,
            callback: { state in
                if case .failed = state {
                    // Should fail
                    Self.fulfill(expectationOne)
                }
        })

        // Copy file
        let sourceTwo = Self.tempDirectory.appendingPathComponent("oludeniz.MOV")
        try? FileManager.default.copyItem(at: sourceOne, to: sourceTwo)
        // Should delete file (on success)
        let destinationTwo = Self.tempDirectory.appendingPathComponent("exported_oludeniz_delete.mov")
        let expectationTwo = XCTestExpectation(description: "Compression & delete")
        expectations.append(expectationTwo)
        _ = await VideoTool.convert(
            source: sourceTwo,
            destination: destinationTwo,
            skipAudio: true,
            overwrite: true,
            deleteSourceFile: true,
            callback: { state in
                switch state {
                case .completed, .cancelled:
                    Task {
                        // Check source deleted
                        let exists = FileManager.default.fileExists(atPath: sourceTwo.path)
                        XCTAssertEqual(exists, false)

                        Self.fulfill(expectationTwo)
                    }
                case .failed(let error):
                    XCTFail(error.localizedDescription)
                default:
                    break
                }
        })

        await fulfillment(of: expectations, timeout: 10 + osAdditionalTimeout)
    }

    func testAudio() async {
        // Default - uncompressed Linear PCM
        await audio("oludeniz.MOV", uid: 0, settings: CompressionAudioSettings(
            codec: .default
        ), data: AudioData(
            format: kAudioFormatMPEG4AAC,
            bitrate: nil,
            sampleRate: 44_100,
            channels: 2
        ))

        // AAC
        await audio("oludeniz.MOV", uid: 1, settings: CompressionAudioSettings(
            codec: .aac
        ), data: AudioData(
            format: kAudioFormatMPEG4AAC,
            bitrate: nil,
            sampleRate: 44_100,
            channels: 2
        ))

        // Opus
        await audio("oludeniz.MOV", uid: 2, settings: CompressionAudioSettings(
            codec: .opus
        ), data: AudioData(
            format: kAudioFormatOpus,
            bitrate: nil,
            sampleRate: 48_000,
            channels: 2
        ))

        // FLAC
        await audio("oludeniz.MOV", uid: 3, settings: CompressionAudioSettings(
            codec: .flac
        ), data: AudioData(
            format: kAudioFormatFLAC,
            bitrate: nil,
            sampleRate: 44_100,
            channels: 2
        ))

        // Skip audio
        await audio("oludeniz.MOV", uid: 4, skipAudio: true)

        // Custom settings
        await audio("oludeniz.MOV", uid: 5, settings: CompressionAudioSettings(
            codec: .opus,
            bitrate: .value(500_000),
            sampleRate: 24_000
        ), data: AudioData(
            format: kAudioFormatOpus,
            bitrate: nil, // 500_000, Can't calculate bitrate for opus correctly in tests, bitsPerChannel is 0
            sampleRate: 24_000,
            channels: 2
        ))
    }

    private func audio(
        _ filename: String,
        uid: Int,
        skipAudio: Bool = false,
        settings: CompressionAudioSettings? = nil,
        data: AudioData? = nil
    ) async {
        let source = Self.mediaDirectory.appendingPathComponent(filename)

        let destination = Self.tempDirectory.appendingPathComponent("exported_\(filename)_\(uid)_audio.mov")
        let expectation = XCTestExpectation(description: "Compression & Audio")
        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            videoSettings: CompressionVideoSettings(bitrate: .value(1_000_000)),
            skipAudio: skipAudio,
            audioSettings: settings,
            overwrite: true,
            callback: { state in
                switch state {
                case .completed, .cancelled:
                    Self.fulfill(expectation)
                case .failed(let error):
                    XCTFail(error.localizedDescription)
                default:
                    break
                }
        })

        await fulfillment(of: [expectation], timeout: 10 + osAdditionalTimeout)

        // Compare resulting file with provided data
        let asset = AVAsset(url: destination)
        let audioTrack = await asset.getFirstTrack(withMediaType: .audio)

        if skipAudio == true && audioTrack == nil {
            // No audio track as expected
        } else if skipAudio == false && audioTrack == nil {
            XCTFail("No audio track found, but required")
        } else {
            let audioDescription = audioTrack!.formatDescriptions.first as! CMFormatDescription
            let basicDescription = audioDescription.audioStreamBasicDescription!

            // Format
            // let mediaSubType = audioDescription.mediaSubType
            XCTAssertEqual(basicDescription.mFormatID, data!.format)

            // Bitrate
            if let bitrate = data!.bitrate {
                let sampleRate = basicDescription.mSampleRate
                let bitsPerChannel = Float64(basicDescription.mBitsPerChannel)
                let channelsPerFrame = Float64(basicDescription.mChannelsPerFrame)

                if sampleRate > 0 && bitsPerChannel > 0 && channelsPerFrame > 0 {
                    let bps = sampleRate * channelsPerFrame * bitsPerChannel
                    let precision = Float64(bitrate) * 0.05
                    XCTAssert(bps > Float64(bitrate) - precision && bps < Float64(bitrate) + precision)
                } else {
                    XCTFail("Can't calculate bitrate for audio #\(uid) \(sampleRate) \(bitsPerChannel) \(channelsPerFrame)")
                }
            }

            // Sample Rate
            if let sampleRate = data!.sampleRate {
                XCTAssertEqual(basicDescription.mSampleRate, Float64(sampleRate))
            }

            // Channels count
            if let channels = data!.channels {
                XCTAssertEqual(basicDescription.mChannelsPerFrame, UInt32(channels))
            }
        }
    }

    /*func testPerformanceExample() {
        self.measure {
            // ...
        }
    }*/
}

/*class TestObserver: NSObject, XCTestObservation {
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        XCTFail("Test case failed: \(description)")
        XCTContext.runActivity(named: "Test Failure Details") { _ in
            if let filePath = filePath {
                XCTAttachment(contentsOfFile: URL(fileURLWithPath: filePath)).lifetime = .keepAlways
            }
            XCTAttachment(plistObject: lineNumber).lifetime = .keepAlways
        }
        XCTContext.runActivity(named: "Abort Test Execution") { _ in
            fatalError("Abort test execution due to failure")
        }
    }
}*/

extension CGSize {
    func almostEqual(to size: CGSize, threshold: CGFloat = 1.0) -> Bool {
        abs(self.width - size.width) <= threshold && abs(self.height - size.height) <= threshold
    }
}

extension AVAssetTrack {
    var naturalSizeWithOrientation: CGSize {
       let transform = preferredTransform // fixedPreferredTransform

       if (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) ||
          (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0) {
           // Portrait
           return CGSize(width: naturalSize.height, height: naturalSize.width)
       } else {
           // Landscape
           return naturalSize
       }
   }
}

let kPERIOD: Double = 0.3
let M_PI_X_2: Double = Double.pi * 2.0

/** The easing (timing function) that an animation should use */
public enum Easing: Int {
    // Source - https://github.com/SteveBarnegren/TweenKit/blob/master/TweenKit/TweenKit/Easing.swift#L28
    // Additional curves can be found here:
    // - https://github.com/manuelCarlos/Easing/blob/main/Sources/Easing/Easing.swift
    // - https://github.com/AugustRush/Stellar/blob/master/Sources/TimingFunction.swift
    
    // Linear
    case linear
    
    // Sine
    case sineIn
    case sineOut
    case sineInOut

    // Exponential
    case exponentialIn
    case exponentialOut
    case exponentialInOut
    
    // Back
    case backIn
    case backOut
    case backInOut
    
    // Bounce
    case bounceIn
    case bounceOut
    case bounceInOut
    
    // Elastic
    case elasticIn
    case elasticOut
    case elasticInOut
    
    public func apply(t: Double) -> Double {
        
        switch self {
            
        // **** Linear ****
        case .linear:
            return t
            
        // **** Sine ****
        case .sineIn:
            return -1.0 * cos(t * (Double.pi/2)) + 1.0
            
        case .sineOut:
            return sin(t * (Double.pi/2))
            
        case .sineInOut:
            return -0.5 * (cos(Double.pi*t) - 1.0)
        
        // **** Exponential ****
        case .exponentialIn:
            return (t==0.0) ? 0.0 : pow(2.0, 10.0 * (t/1.0 - 1.0)) - 1.0 * 0.001;
            
        case .exponentialOut:
            return (t==1.0) ? 1.0 : (-pow(2.0, -10.0 * t/1.0) + 1.0);
            
        case .exponentialInOut:
            var t = t
            t /= 0.5;
            if (t < 1.0) {
                t = 0.5 * pow(2.0, 10.0 * (t - 1.0))
            }
            else {
                t = 0.5 * (-pow(2.0, -10.0 * (t - 1.0) ) + 2.0);
            }
            return t;
        
        // **** Back ****
        case .backIn:
            let overshoot = 1.70158
            return t * t * ((overshoot + 1.0) * t - overshoot);
            
        case .backOut:
            let overshoot = 1.70158
            var t = t
            t = t - 1.0;
            return t * t * ((overshoot + 1.0) * t + overshoot) + 1.0;
            
        case .backInOut:
            let overshoot = 1.70158 * 1.525
            var t = t
            t = t * 2.0;
            if (t < 1.0) {
                return (t * t * ((overshoot + 1.0) * t - overshoot)) / 2.0;
            }
            else {
                t = t - 2.0;
                return (t * t * ((overshoot + 1.0) * t + overshoot)) / 2.0 + 1.0;
            }
            
        // **** Bounce ****
        case .bounceIn:
            var newT = t
            if(t != 0.0 && t != 1.0) {
                newT = 1.0 - bounceTime(t: 1.0 - t)
            }
            return newT;
            
        case .bounceOut:
            var newT = t;
            if(t != 0.0 && t != 1.0) {
                newT = bounceTime(t: t)
            }
            return newT;
            
        case .bounceInOut:
            let newT: Double
            if( t == 0.0 || t == 1.0) {
                newT = t;
            }
            else if (t < 0.5) {
                var t = t
                t = t * 2.0;
                newT = (1.0 - bounceTime(t: 1.0-t) ) * 0.5
            } else {
                newT = bounceTime(t: t * 2.0 - 1.0) * 0.5 + 0.5
            }
            
            return newT;
            
        // **** Elastic ****
        case .elasticIn:
            var newT = 0.0
            if (t == 0.0 || t == 1.0) {
                newT = t
            }
            else {
                var t = t
                let s = kPERIOD / 4.0;
                t = t - 1;
                newT = -pow(2, 10 * t) * sin( (t-s) * M_PI_X_2 / kPERIOD);
            }
            return newT;
            
        case .elasticOut:
            var newT = 0.0
            if (t == 0.0 || t == 1.0) {
                newT = t
            } else {
                let s = kPERIOD / 4;
                newT = pow(2.0, -10.0 * t) * sin( (t-s) * M_PI_X_2 / kPERIOD) + 1
            }
            return newT
            
        case .elasticInOut:
            var newT = 0.0;
            
            if( t == 0.0 || t == 1.0 ) {
                newT = t;
            }
            else {
                var t = t
                t = t * 2.0;
                let s = kPERIOD / 4;
                
                t = t - 1.0;
                if( t < 0 ) {
                    newT = -0.5 * pow(2, 10.0 * t) * sin((t - s) * M_PI_X_2 / kPERIOD);
                }
                else{
                    newT = pow(2, -10.0 * t) * sin((t - s) * M_PI_X_2 / kPERIOD) * 0.5 + 1.0;
                }
            }
            return newT;
        }
    }
    
    // Helpers
    
    func bounceTime(t: Double) -> Double {
        
        var t = t
        
        if (t < 1.0 / 2.75) {
            return 7.5625 * t * t
        }
        else if (t < 2.0 / 2.75) {
            t -= 1.5 / 2.75
            return 7.5625 * t * t + 0.75
        }
        else if (t < 2.5 / 2.75) {
            t -= 2.25 / 2.75
            return 7.5625 * t * t + 0.9375
        }
        
        t -= 2.625 / 2.75
        return 7.5625 * t * t + 0.984375
    }
    
    func interpolate(from: CGFloat, to: CGFloat, with progress: CGFloat) -> CGFloat {
        return from + (to - from) * self.apply(t: progress)
    }

    func interpolate(from: CGColor, to: CGColor, with progress: CGFloat) -> CGColor {
        guard let fromComponents = from.components,
              let toComponents = to.components else {
            return from
        }

        let curvedProgress = self.apply(t: progress)
        let interpolatedComponents = zip(fromComponents, toComponents).map { (fromComponent, toComponent) -> CGFloat in
            return fromComponent + (toComponent - fromComponent) * curvedProgress
        }

        return CGColor(colorSpace: from.colorSpace ?? CGColorSpaceCreateDeviceRGB(), components: interpolatedComponents) ?? from
    }
    
    static func `default`(from: CGFloat, to: CGFloat, with progress: CGFloat) -> CGFloat {
        Self.linear.interpolate(from: from, to: to, with: progress)
    }
}
#endif
