// swiftlint:disable force_try force_cast
#if canImport(MediaToolSwift)
@testable import MediaToolSwift
import XCTest
import Foundation
import AVFoundation
import VideoToolbox

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
            Config(
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
            ),
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
                file.pathExtension.lowercased() == "mov" ||
                file.pathExtension.lowercased() == "mp4" ||
                file.pathExtension.lowercased() == "m4v"
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

    func testLosslessCut() async {
        let expectation = XCTestExpectation(description: "Losslessly cut HEVC")
        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")
        let destination = Self.tempDirectory.appendingPathComponent("lossless_cut_oludeniz.mov")
        try? FileManager.default.removeItem(at: destination)

        let asset = AVAsset(url: source)
        let reader = try! AVAssetReader(asset: asset)
        let writer = try! AVAssetWriter(outputURL: destination, fileType: .mov)

        let videoTrack = await asset.getFirstTrack(withMediaType: .video)

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack!, outputSettings: nil)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)

        reader.add(videoOutput)
        writer.add(videoInput)

        videoInput.transform = videoTrack!.fixedPreferredTransform

        // Time Scale
        let timeScale = videoTrack!.naturalTimeScale // asset.duration.timescale
        videoInput.mediaTimeScale = timeScale
        writer.movieTimeScale = timeScale
        // TODO: Time Scale should be adjusted as frame rate of video is changed on trimming - https://developer.apple.com/library/archive/qa/qa1447/_index.html

        // Time Range and Duration
        let startTime: CMTime = CMTime(seconds: 5, preferredTimescale: timeScale)
        let endTime: CMTime = CMTime(seconds: asset.duration.seconds, preferredTimescale: timeScale)
        reader.timeRange = CMTimeRange(start: startTime, end: endTime) // CMTimeRangeMake(start: 5, duration: 3)

        writer.shouldOptimizeForNetworkUse = true

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let videoQueue = DispatchQueue(label: "MediaToolSwiftTests.video.queue")
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let newPresentationTime = CMTimeSubtract(presentationTime, startTime)
                    
                    let status = CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: newPresentationTime)
                    if status == noErr {
                        videoInput.append(sampleBuffer)
                    }
                } else {
                    videoInput.markAsFinished()
                    
                    writer.finishWriting {
                        if writer.status == .completed {
                            Self.fulfill(expectation)
                        } else {
                            XCTFail(writer.error?.localizedDescription ?? "Unknown error")
                        }
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5)
    }

    func testOne() async {
        let expectation = XCTestExpectation(description: "Test video")
        let source = Self.mediaDirectory.appendingPathComponent("oludeniz.MOV")
        let destination = Self.tempDirectory.appendingPathComponent("compressed_oludeniz.MOV")

        _ = await VideoTool.convert(
            source: source,
            destination: destination,
            fileType: .mov,
            videoSettings: CompressionVideoSettings(
                codec: .hevc,
                frameRate: 15
            ),
             skipAudio: true,
            /*audioSettings: CompressionAudioSettings(
                codec: .alac
            ),*/
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

        await fulfillment(of: [expectation], timeout: 15 + osAdditionalTimeout)
    }

    func testVideos() async {
        var expectations: [XCTestExpectation] = []

        for file in configurations {
            let source = Self.mediaDirectory.appendingPathComponent(file.filename)

            #if targetEnvironment(simulator)
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

                #if targetEnvironment(simulator)
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

        await fulfillment(of: expectations, timeout: 20 + osAdditionalTimeout * Double(expectations.count))

        for file in configurations {
            #if targetEnvironment(simulator)
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

                #if targetEnvironment(simulator)
                if config.videoSettings.codec == .proRes4444 {
                    continue
                }
                #endif

                let destination = Self.tempDirectory.appendingPathComponent(config.output.filename)

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
                codec: .hevc,
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
#endif
