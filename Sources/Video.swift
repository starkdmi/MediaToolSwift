import AVFoundation
import CoreImage
import VideoToolbox
import Accelerate

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Video related singletone interface
public struct VideoTool {

    /// Compress a video file.
    public static func convert(
        source: URL,
        destination: URL,
        fileType: VideoFileType = .mov,
        videoSettings: CompressionVideoSettings = CompressionVideoSettings(),
        optimizeForNetworkUse: Bool = true,
        skipAudio: Bool = false,
        audioSettings: CompressionAudioSettings? = nil,
        skipSourceMetadata: Bool = false,
        customMetadata: [AVMetadataItem] = [],
        copyExtendedFileMetadata: Bool = true,
        cacheDirectory: URL? = nil,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false,
        progressQueue: DispatchQueue = .main,
        callback: @escaping (CompressionState) -> Void
    ) async -> CompressionTask {
        await convertImpl(
            source: source,
            destination: destination,
            fileType: fileType,
            videoSettings: videoSettings,
            optimizeForNetworkUse: optimizeForNetworkUse,
            skipAudio: skipAudio,
            audioSettings: audioSettings,
            skipSourceMetadata: skipSourceMetadata,
            customMetadata: customMetadata,
            copyExtendedFileMetadata: copyExtendedFileMetadata,
            cacheDirectory: cacheDirectory,
            overwrite: overwrite,
            deleteSourceFile: deleteSourceFile,
            progressQueue: progressQueue,
            callback: callback
        )
    }

    public static func getInfo(source: URL) async throws -> VideoInfo {
        // Check source file existence
        if !FileManager.default.fileExists(atPath: source.path) {
            // Also caused by insufficient permissions
            throw CompressionError.sourceFileNotFound
        }

        let asset = AVAsset(url: source)

        // Get first video track
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        let analysis = try await VideoTrackAnalyzer().analyze(track: videoTrack, asset: asset)

        // Resolution
        let size = analysis.naturalSize.oriented(analysis.orientation)
        // Duration
        let duration = analysis.duration.seconds
        // Frame rate
        let frameRate = analysis.nominalFrameRate
        // Total frames amount
        let totalFrames = Int64(ceil(duration * Double(frameRate)))
        // Video bitrate
        let videoBitrate = analysis.estimatedDataRate.rounded()
        // File size
        // let filesize = videoTrack.totalSampleDataLength

        // Video Codec
        let videoCodec = analysis.codec
        // Alpha channel presence
        let hasAlpha = analysis.hasAlpha
        // HDR
        let isHDR = analysis.isHDR // videoTrack.hasMediaCharacteristic(.containsHDRVideo)

        // Load first audio track
        let audioTrack = await asset.getFirstTrack(withMediaType: .audio)

        // Audio info
        let hasAudio = audioTrack != nil
        var audioCodec: CompressionAudioCodec?
        var audioBitrate: Int?
        if let audioTrack {
            let audioAnalysis = try await AudioTrackAnalyzer().analyze(track: audioTrack)
            audioCodec = audioAnalysis.codec
            audioBitrate = audioAnalysis.estimatedBitrate
        }

        // Extended info
        let rawData = FileExtendedAttributes.getExtendedMetadata(from: source.path)
        let extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: rawData)

        return VideoInfo(
            url: source,
            resolution: size,
            // orientation: videoTrack.orientation,
            frameRate: Int(frameRate.rounded()),
            totalFrames: Int(totalFrames),
            duration: duration,
            videoCodec: videoCodec,
            videoBitrate: Int(videoBitrate),
            hasAlpha: hasAlpha,
            isHDR: isHDR,
            hasAudio: hasAudio,
            audioCodec: audioCodec,
            audioBitrate: audioBitrate,
            extendedInfo: extendedInfo
        )
    }

    // MARK: Video Thumbnail

    /// Generate multiple CGImage thumbnails
    /// - Parameters:
    ///     - asset: Input video asset
    ///     - seconds: Array of points in seconds to generate thumbnails at, can differ based on tolerance
    ///     - size: Thumbnail size to fit in
    ///     - transfrom: Apply preferred source video tranformations if `true`
    ///     - timeToleranceBefore: Time tolerance before specified time, in seconds
    ///     - timeToleranceAfter: Time tolerance after specified time, in seconds
    ///     - completion: The completion callback with an array of thumbnail objects as images
    public static func thumbnailImages(
        for asset: AVAsset,
        at seconds: [Double],
        size: CGSize? = nil,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity,
        completion: @escaping ([VideoThumbnail]) -> Void
    ) throws {
        // Get video track
        #if os(visionOS)
        let videoTrack = try? Sync.wait {
            let tracks = await asset.getTracks(withMediaType: .video)
            return tracks?.first
        }
        #else
        let videoTrack = asset.tracks(withMediaType: .video).first
        #endif
        guard let videoTrack = videoTrack else {
            throw CompressionError.videoTrackNotFound
        }

        #if os(visionOS)
        let nominalFrameRate = (try? Sync.wait {
            await videoTrack.getNominalFrameRate()
        }) ?? 0
        let videoSize = (try? Sync.wait {
            await videoTrack.getNaturalSizeWithOrientation()
        }) ?? .zero
        #else
        let nominalFrameRate = videoTrack.nominalFrameRate
        let transform = videoTrack.preferredTransform
        let orientation: VideoOrientation
        if (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) ||
            (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0) {
            orientation = .portrait
        } else {
            orientation = .landscape
        }
        let videoSize = videoTrack.naturalSize.oriented(orientation)
        #endif

        // Convert seconds to `CMTime`s
        // let timeScale: CMTimeScale = max(600, CMTimeScale(videoTrack.nominalFrameRate))
        var timeScale = CMTimeScale(nominalFrameRate)
        if timeScale < 240 { timeScale = 240 } // 60, 240, 600
        let seconds = seconds.map({ CMTimeMakeWithSeconds($0, preferredTimescale: timeScale) })

        // AVAssetImageGenerator - https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/creating_images_from_a_video_asset
        let generator = AVAssetImageGenerator(asset: asset)

        // Transform video frame
        generator.appliesPreferredTrackTransform = transfrom

        // Size to fit in
        if var size = size {
            // `AVAssetImageGenerator.maximumSize` needs a value larger than required size by 0.5-1.0 pixels
            size.width += 0.5 // 1.0
            size.height += 0.5 // 1.0
            if size.width < videoSize.width || size.height < videoSize.height {
                let maximumSize: CGSize
                if videoSize.width > videoSize.height {
                    maximumSize = CGSize(width: videoSize.width / videoSize.height * size.width, height: size.height)
                } else if videoSize.height > videoSize.width {
                    maximumSize = CGSize(width: size.width, height: videoSize.height / videoSize.width * size.height)
                } else {
                    maximumSize = CGSize(width: videoSize.width, height: videoSize.height)
                }
                generator.maximumSize = maximumSize
            }
        }

        // Tolerance before specified time
        switch timeToleranceBefore {
        case .zero:
            generator.requestedTimeToleranceBefore = .zero
        case .infinity:
            // default to kCMTimePositiveInfinity
            break
        default:
            generator.requestedTimeToleranceBefore = CMTime(seconds: timeToleranceBefore, preferredTimescale: timeScale)
        }

        // Tolerance after specified time
        switch timeToleranceAfter {
        case .zero:
            generator.requestedTimeToleranceBefore = .zero
        case .infinity:
            // default to kCMTimePositiveInfinity
            break
        default:
            generator.requestedTimeToleranceBefore = CMTime(seconds: timeToleranceAfter, preferredTimescale: timeScale)
        }

        guard !seconds.isEmpty else {
            completion([])
            return
        }

        let nsSeconds = seconds.map({ NSValue(time: $0) })
        let collector = VideoThumbnailCollector(expectedCount: seconds.count, completion: completion)
        generator.generateCGImagesAsynchronously(forTimes: nsSeconds, completionHandler: { (requestedTime, image, actualTime, _, _) in
            collector.receive(
                image: image,
                requestedTime: requestedTime.seconds,
                actualTime: actualTime.seconds
            )
        })
    }

    /// Generate multiple file thumbnails
    /// - Parameters:
    ///     - asset: Input video asset
    ///     - requests: Array of points in seconds to generate thumbnails at and url to save file at
    ///     - settings: Output images settings
    ///     - transfrom: Apply preferred source video tranformations if `true`
    ///     - timeToleranceBefore: Time tolerance before specified time, in seconds
    ///     - timeToleranceAfter: Time tolerance after specified time, in seconds
    ///     - completion: The completion callback with array of file thumbnail objects or an error
    public static func thumbnailFiles(
        of asset: AVAsset,
        at requests: [VideoThumbnailRequest],
        settings: ImageSettings,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity,
        completion: @escaping (Result<[VideoThumbnailFile], CompressionError>) -> Void
    ) {
        var thumbSize: CGSize?
        var crop: Crop?
        switch settings.size {
        case .fit(let size):
            thumbSize = size
        case .crop(let size, let options):
            thumbSize = size
            crop = options
        case .original:
            break
        }

        // Warning: `thumbSize` set the min size, not the fitting area, so the additional resizing will be applied if not `nil`
        let shouldResize = thumbSize != nil

        /*var isHDRVideo: Bool?
        if let videoTrack = await asset.getFirstTrack(withMediaType: .video) {
            let videoDesc = videoTrack.formatDescriptions.first as! CMFormatDescription
            isHDRVideo = videoDesc.isHDRVideo
        }*/

        // Request the images at specific times
        let seconds = requests.map({ $0.time })
        do {
            try thumbnailImages(for: asset, at: seconds, size: thumbSize, transfrom: transfrom, timeToleranceBefore: timeToleranceBefore, timeToleranceAfter: timeToleranceAfter) { items in
                if items.isEmpty {
                    completion(.success([]))
                    return
                }

                // `CImage` variables
                lazy var context = CIContext(options: [.highQualityDownsample: true])
                // `vImage` variables
                var format: vImage_CGImageFormat?
                var tempBuffer: TemporaryBuffer?
                var converterIn: vImageConverter?, converterOut: vImageConverter?

                var thumbnails: [VideoThumbnailFile] = []
                for index in 0 ..< items.count {
                    let item = items[index]
                    var image = item.image
                    let url = requests[index].url

                    var ciImage: CIImage?
                    // Warning: video thumbnails using generator are always 8 bit per component
                    let isHDR = image.bitsPerComponent > 8 // || isHDRVideo
                    let fallbackToCIImage = settings.preferredFramework == .ciImage || isHDR || settings.format == .heif || settings.format == .heif10

                    // Process as `CIImage`
                    if fallbackToCIImage {
                        // Convert to CIImage
                        ciImage = CIImage(cgImage: image, options: [.applyOrientationProperty: false])

                        // Apply edits
                        ciImage = ciImage?.edit(
                            operations: settings.edit,
                            size: settings.size,
                            shouldResize: shouldResize,
                            hasAlpha: image.hasAlpha,
                            preserveAlpha: settings.preserveAlphaChannel,
                            backgroundColor: settings.backgroundColor,
                            index: index
                        )
                    }

                    // Process as `CGImage` using `vImage`
                    if ciImage == nil || !fallbackToCIImage {
                        if !settings.edit.isEmpty || (!settings.preserveAlphaChannel && image.hasAlpha) || shouldResize {
                            if format == nil {
                                format = vImage_CGImageFormat(image)
                                converterIn = vImageConverter.create(from: format)
                                converterOut = vImageConverter.create(to: format)
                            }

                            if let edited = try? vImage.edit(
                                image: image,
                                operations: settings.edit,
                                size: settings.size,
                                shouldResize: shouldResize,
                                hasAlpha: image.hasAlpha,
                                preserveAlpha: settings.preserveAlphaChannel,
                                backgroundColor: settings.backgroundColor,
                                index: index,
                                format: format,
                                converterIn: converterIn,
                                converterOut: converterOut,
                                tempBuffer: &tempBuffer // doesn't support parallel threads, equals to `nil`
                            ) {
                                image = edited
                            }
                        } else if let options = crop {
                            // Crop using `CGImage` to prevent conversion to `vImage` just for cropping
                            if let cropped = image.crop(using: options) {
                                image = cropped
                            }

                            // Convert color space for BMP images, as it doesn't support some video codec color spaces
                            if settings.format == .bmp,
                                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                                let converted = image.convertColorSpace(to: colorSpace) {
                                image = converted
                            }
                        }
                    }

                    do {
                        // Image editing reuses the vImage conversion state above, so
                        // encode sequentially rather than sharing it across queues.
                        let frames = [ImageFrame(cgImage: image, ciImage: ciImage)]
                        try ImageTool.encode(frames, at: url, settings: settings)

                        let size = ciImage?.extent.size ?? image.size
                        thumbnails.append(VideoThumbnailFile(url: url, format: settings.format, size: size, time: item.actualTime))
                    } catch {
                        continue
                    }
                }

                if thumbnails.isEmpty {
                    completion(.failure(CompressionError.failedToGenerateThumbnails))
                } else {
                    completion(.success(thumbnails))
                }
            }
        } catch let error as CompressionError {
            completion(.failure(error))
        } catch {
            completion(.failure(CompressionError.failedToGenerateThumbnails))
        }
    }
}

/// Synchronizes callbacks from AVAssetImageGenerator without requiring callers
/// to make their thumbnail or completion types Sendable.
private final class VideoThumbnailCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedCount: Int
    private let completion: ([VideoThumbnail]) -> Void
    private var remainingCount: Int
    private var thumbnails: [VideoThumbnail] = []
    private var completed = false

    init(expectedCount: Int, completion: @escaping ([VideoThumbnail]) -> Void) {
        self.expectedCount = expectedCount
        self.remainingCount = expectedCount
        self.completion = completion
        thumbnails.reserveCapacity(expectedCount)
    }

    func receive(image: CGImage?, requestedTime: Double, actualTime: Double) {
        let result: [VideoThumbnail]?

        lock.lock()
        if let image {
            thumbnails.append(
                VideoThumbnail(
                    image: image,
                    requestedTime: requestedTime,
                    actualTime: actualTime
                )
            )
        }
        remainingCount -= 1

        if !completed && (remainingCount <= 0 || thumbnails.count == expectedCount) {
            completed = true
            result = thumbnails
        } else {
            result = nil
        }
        lock.unlock()

        if let result {
            completion(result)
        }
    }
}
