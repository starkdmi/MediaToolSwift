// swiftlint:disable force_try force_cast
#if canImport(MediaToolSwift)
@testable import MediaToolSwift
import XCTest
import Foundation
import AVFoundation
import VideoToolbox

// Run from project directory `cd MediaToolSwift` with `swift test`

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
    let fileType: CompressionFileType
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
let configurations: [ConfigList] = [
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
                    size: CGSize(width: 720.0, height: 720.0)
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
                    bitrate: 880_000,
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
                    bitrate: .encoder,
                    preserveAlphaChannel: true
                ),
                output: Parameters(
                    filename: "exported_transparent_ball_prores.mov",
                    filesize: nil,
                    resolution: CGSize(width: 1280.0, height: 720.0),
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
            /*Config(
                videoSettings: CompressionVideoSettings(
                    codec: .proRes4444,
                    bitrate: .encoder,
                    size: CGSize(width: 3000.0, height: 4000.0),
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
            ),*/
            Config(
                videoSettings: CompressionVideoSettings(
                    size: CGSize(width: 1280.0, height: 1280.0)
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
                    size: CGSize(width: 720.0, height: 720.0),
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

    // INFO: VP9 and AV1 are not supported yet
    // Big Buck Bunny VP9 - https://test-videos.co.uk/bigbuckbunny/webm-vp9
    // Big Buck Bunny AV1 - https://test-videos.co.uk/bigbuckbunny/webm-av1

    // Jellyfish - https://test-videos.co.uk/jellyfish/mp4-h265
    // Chromium test videos - https://github.com/chromium/chromium/tree/master/media/test/data
    // WebM test videos - https://github.com/webmproject/libwebm/tree/main/testing/testdata
]

// Download file from url and save to local directory 
func downloadFile(url: String, path: String) async throws {
    let url: URL = URL(string: url)!
    let (data, _) = try await URLSession.shared.data(from: url)
    try data.write(to: URL(fileURLWithPath: path))
}

class MediaToolSwiftTests: XCTestCase {

    override func setUp() {
        super.setUp()

        Task {
            // Fetch all video files
            for config in configurations {
                if let url = config.url {
                    let path: String = "./Tests/media/\(config.filename)"
                    if !FileManager.default.fileExists(atPath: path) {
                        try! await downloadFile(url: url, path: path)
                    }
                }
            }
        }

        let tempDirectory = URL(fileURLWithPath: "./Tests/media/temp")
        var isDirectory: ObjCBool = true
        if !FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDirectory) {
            try! FileManager.default.createDirectory(atPath: tempDirectory.path, withIntermediateDirectories: false)
        }
    }

    override func tearDown() {
        let tempDirectory = URL(fileURLWithPath: "./Tests/media/temp")

        // Delete system AVAssetWriter temp files
        do {
            let files = try! FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in files where file.pathExtension == "" {
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

    /*func testOne() async {
        let expectation = XCTestExpectation(description: "Test video file")
        let source = URL(fileURLWithPath: "./Tests/media/oludeniz.MOV")
        let destination = URL(fileURLWithPath: "./Tests/media/temp/oludeniz.mov")

        await VideoTool.convert(
            source: source,
            destination: destination,
            fileType: .mov,
            videoSettings: CompressionVideoSettings(codec: .hevcWithAlpha, size: CGSize(width: 4000.0, height: 3000.0), frameRate: 30, preserveAlphaChannel: false),
            // skipAudio: true,
            audioSettings: CompressionAudioSettings(codec: .aac, bitrate: 96_000),
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

        await fulfillment(of: [expectation], timeout: 5)
    }*/

    func testVideos() async {
        var expectations: [XCTestExpectation] = []

        for file in configurations {
            let path = "./Tests/media/\(file.filename)"
            let source = URL(fileURLWithPath: path)

            for config in file.configs {
                let destination = URL(fileURLWithPath: "./Tests/media/temp/\(config.output.filename)")
                let expectation = XCTestExpectation(description: "Video processing")

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
                            print(error)
                            XCTFail(error.localizedDescription)
                        default:
                            break
                        }
                })
                expectations.append(expectation)
            }
        }

        await fulfillment(of: expectations, timeout: 20)

        for file in configurations {
            for config in file.configs {
                // Test results
                // 1. video
                // 2. file size
                // 3. resolution
                // 4. bitrate
                // 5. frame rate
                // 6? duration in seconds
                // 7? has alpha channel

                let destination = URL(fileURLWithPath: "./Tests/media/temp/\(config.output.filename)")

                // Init video asset
                let asset = AVAsset(url: destination)
                guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
                    XCTFail("No video track found in resulting file")
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
                    XCTAssertEqual(mediaSubTypeString, "'hvc1'")
                } else {
                    XCTAssertEqual(mediaSubTypeString, "'\(config.output.videoCodec.rawValue)'")
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
                        XCTAssertLessThanOrEqual(fileSize, UInt64(original))
                    }
                }

                // 3. Resolution
                let videoSize = videoTrack.naturalSizeWithOrientation
                XCTAssertEqual(videoSize, config.output.resolution)

                // 4. Bitrate 
                let estimatedDataRate = videoTrack.estimatedDataRate
                if let bitrate = config.output.bitrate {
                    if bitrate >= 0 {
                        // should equal the value +- 5%
                        let precision = Float(bitrate) * 0.05
                        XCTAssert(estimatedDataRate > Float(bitrate) - precision && estimatedDataRate < Float(bitrate) + precision)
                    } else if bitrate < 0 {
                        // should be less than input
                        XCTAssertLessThanOrEqual(estimatedDataRate, Float(file.input.bitrate ?? 0))
                    }
                }

                // 5. Frame rate | FPS
                let frameRate = videoTrack.nominalFrameRate
                if config.output.frameRate == nil {
                    // should be less then input
                    XCTAssertLessThanOrEqual(frameRate, Float(file.input.frameRate ?? 0))
                } else {
                    // equals the value
                    XCTAssertLessThanOrEqual(frameRate, Float(config.output.frameRate ?? 0))
                }

                // 6. Duration
                if let duration = config.output.duration {
                    XCTAssert(abs(asset.duration.seconds - duration) < 0.1)
                }

                // 7. Alpha channel presence
                if let hasAlpha = config.output.hasAlpha {
                    let hasAlphaChannel = videoDesc.hasAlphaChannel
                    XCTAssertEqual(hasAlphaChannel, hasAlpha)
                }
            }
        }
    }

    func testMetadata() async {
        var expectations: [XCTestExpectation] = []

        let path = "./Tests/media/oludeniz.MOV"
        let source = URL(fileURLWithPath: path)

        let metadataItem = AVMutableMetadataItem()
        metadataItem.key = AVMetadataKey.commonKeyTitle as NSString
        metadataItem.keySpace = AVMetadataKeySpace.common
        metadataItem.value = "Custom Title" as NSString
        metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String

        let customMetadata: [AVMetadataItem] = [metadataItem]

        // Add custom metadata, check existing for correctness
        let destinationOne = URL(fileURLWithPath: "./Tests/media/temp/exported_oludeniz_metadata.mov")
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
        let destinationTwo = URL(fileURLWithPath: "./Tests/media/temp/exported_oludeniz_no_metadata.mov")
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

        await fulfillment(of: expectations, timeout: 20)
    }

    func testCancellation() async {
        let path = "./Tests/media/oludeniz.MOV"
        let source = URL(fileURLWithPath: path)

        let destination = URL(fileURLWithPath: "./Tests/media/temp/exported_oludeniz_cancel.mov")
        let expectation = XCTestExpectation(description: "Compression & cancellation")
        var status: CompressionState?
        let task = await VideoTool.convert(
            source: source,
            destination: destination,
            // Slow down the compression
            videoSettings: CompressionVideoSettings(
                codec: .proRes4444,
                bitrate: .encoder
            ),
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

        await fulfillment(of: [expectation], timeout: 10)

        // Check the state
        XCTAssertEqual(status, .cancelled)

        // Check no files created 
        let exists = FileManager.default.fileExists(atPath: destination.path)
        XCTAssertEqual(exists, false)
    }

    func testFileOptions() async {
        var expectations: [XCTestExpectation] = []

        // Copy file
        let sourceOne = URL(fileURLWithPath: "./Tests/media/oludeniz.MOV")
        let destinationOne = URL(fileURLWithPath: "./Tests/media/temp/exported_oludeniz_overwrite.mov")
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
        let sourceTwo = URL(fileURLWithPath: "./Tests/media/temp/oludeniz.MOV")
        try? FileManager.default.copyItem(at: sourceOne, to: sourceTwo)
        // Should delete file (on success)
        let destinationTwo = URL(fileURLWithPath: "./Tests/media/temp/exported_oludeniz_delete.mov")
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

        await fulfillment(of: expectations, timeout: 10)
    }

    func testAudio() async {
        // Default - uncompressed Linear PCM 
        await audio("oludeniz.MOV", uid: 0, settings: CompressionAudioSettings(
            codec: .default
        ), data: AudioData(
            format: kAudioFormatLinearPCM,
            bitrate: 2_116_000,
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
            bitrate: 500_000,
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
        let path = "./Tests/media/\(filename)"
        let source = URL(fileURLWithPath: path)

        let destination = URL(fileURLWithPath: "./Tests/media/temp/exported_\(filename)_\(uid)_audio.mov")
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

        await fulfillment(of: [expectation], timeout: 10)

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
                    XCTFail("Can't calculate bitrate for audio #\(uid)")
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
#endif
