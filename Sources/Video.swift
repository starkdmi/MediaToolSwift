@preconcurrency import AVFoundation
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
    ///
    /// Returns when the conversion finishes, throwing the underlying error on
    /// failure and `CancellationError` when the conversion is cancelled.
    ///
    /// Pass a `task` you created yourself to observe `progress` and
    /// `writingProgress` while the conversion runs, or to cancel it from outside
    /// the awaiting context. Cancelling the enclosing Swift `Task` cancels the
    /// conversion too, so a `task` is only needed for progress reporting or for
    /// cancellation driven by something other than task cancellation.
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
        task: CompressionTask? = nil
    ) async throws -> VideoInfo {
        let task = task ?? CompressionTask(destination: destination)
        guard task.claimForConversion(destination: destination) else {
            throw CompressionError.taskAlreadyUsed
        }
        let holder = ConversionResultHolder<VideoInfo>()

        // Start before suspending: the pipeline may reach a terminal state
        // during preparation, and the holder buffers it until `attach`.
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
            task: task,
            callback: { holder.deliver($0) }
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { holder.attach($0) }
        } onCancel: {
            task.cancel()
        }
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
        let totalFrames = analysis.totalFrames
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
    /// - Returns: The generated thumbnails. Times that produced no image are omitted.
    ///
    /// `AVAsset` is not `Sendable`, so this method inherits the caller's
    /// isolation instead of hopping to the generic executor. Without that, an
    /// actor-isolated asset — the common `@MainActor` view-model case — could
    /// not be passed in at all. The asset is only read here, and the decode
    /// itself runs on AVFoundation's own threads.
    public static func thumbnailImages(
        for asset: AVAsset,
        at seconds: [Double],
        size: CGSize? = nil,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> [VideoThumbnail] {
        guard size?.hasFinitePositiveDimensions ?? true,
              seconds.allSatisfy(\.isFinite),
              isValidThumbnailTolerance(timeToleranceBefore),
              isValidThumbnailTolerance(timeToleranceAfter) else {
            throw CompressionError.failedToGenerateThumbnails
        }

        // Get video track. The async property API is unconditional at the
        // package's deployment targets, so every platform takes one path.
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        let nominalFrameRate = await videoTrack.getNominalFrameRate()
        let videoSize = await videoTrack.getNaturalSizeWithOrientation()

        guard videoSize.hasFinitePositiveDimensions else {
            throw CompressionError.failedToGenerateThumbnails
        }

        // Convert seconds to `CMTime`s
        // let timeScale: CMTimeScale = max(600, CMTimeScale(videoTrack.nominalFrameRate))
        guard nominalFrameRate.isFinite, nominalFrameRate >= 0 else {
            throw CompressionError.failedToGenerateThumbnails
        }
        let boundedFrameRate = min(Double(nominalFrameRate), Double(CMTimeScale.max))
        var timeScale = CMTimeScale(boundedFrameRate)
        if timeScale < 240 { timeScale = 240 } // 60, 240, 600
        let maximumSeconds = Double(Int64.max).nextDown / Double(timeScale)
        guard seconds.allSatisfy({ abs($0) <= maximumSeconds }),
              thumbnailToleranceFits(timeToleranceBefore, maximumSeconds: maximumSeconds),
              thumbnailToleranceFits(timeToleranceAfter, maximumSeconds: maximumSeconds) else {
            throw CompressionError.failedToGenerateThumbnails
        }
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
            generator.requestedTimeToleranceAfter = .zero
        case .infinity:
            // default to kCMTimePositiveInfinity
            break
        default:
            generator.requestedTimeToleranceAfter = CMTime(seconds: timeToleranceAfter, preferredTimescale: timeScale)
        }

        guard !seconds.isEmpty else {
            return []
        }

        let nsSeconds = seconds.map({ NSValue(time: $0) })

        // `withTaskCancellationHandler` runs `onCancel` immediately when the
        // task is already cancelled, which is *before* the operation body
        // starts generating. Cancelling a generator that has no pending
        // requests does nothing, so bail out here instead of decoding every
        // requested time and throwing the result away afterwards.
        try Task.checkCancellation()

        // `AVAssetImageGenerator` is not `Sendable`, but the cancellation
        // handler only calls `cancelAllCGImageGeneration()`, which AVFoundation
        // documents as safe to call from any thread.
        nonisolated(unsafe) let cancellableGenerator = generator

        let thumbnails = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let collector = VideoThumbnailCollector(requestedTimes: seconds) { thumbnails in
                    continuation.resume(returning: thumbnails)
                }
                generator.generateCGImagesAsynchronously(forTimes: nsSeconds, completionHandler: { (requestedTime, image, actualTime, _, _) in
                    collector.receive(
                        image: image,
                        requestedTime: requestedTime,
                        actualTime: actualTime.seconds
                    )
                })

                // Cancellation landing between the check above and this line
                // runs `onCancel` while the generator still has nothing queued,
                // and `cancelAllCGImageGeneration()` only affects pending
                // requests. Re-checking now that the requests exist closes that
                // window: either this sees the flag, or `onCancel` ran late
                // enough for its own call to reach real work.
                if Task.isCancelled {
                    cancellableGenerator.cancelAllCGImageGeneration()
                }
            }
        } onCancel: {
            // Cancelled requests still invoke the completion handler, so the
            // collector completes and the continuation resumes rather than
            // leaking.
            cancellableGenerator.cancelAllCGImageGeneration()
        }

        try Task.checkCancellation()
        return thumbnails
    }

    /// Generate multiple file thumbnails
    /// - Parameters:
    ///     - asset: Input video asset
    ///     - requests: Array of points in seconds to generate thumbnails at and url to save file at
    ///     - settings: Output images settings
    ///     - transfrom: Apply preferred source video tranformations if `true`
    ///     - timeToleranceBefore: Time tolerance before specified time, in seconds
    ///     - timeToleranceAfter: Time tolerance after specified time, in seconds
    /// - Returns: The written thumbnail files.
    ///
    /// Inherits the caller's isolation so a non-`Sendable` `AVAsset` can be
    /// passed from an actor — see ``thumbnailImages(for:at:size:transfrom:timeToleranceBefore:timeToleranceAfter:isolation:)``.
    /// The image editing and encoding is handed to `encodeThumbnails` so it
    /// does not run on the caller's actor.
    public static func thumbnailFiles(
        of asset: AVAsset,
        at requests: [VideoThumbnailRequest],
        settings: ImageSettings,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> [VideoThumbnailFile] {
        guard settings.hasValidGeometry else {
            throw CompressionError.failedToGenerateThumbnails
        }

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
        let items = try await thumbnailImages(
            for: asset,
            at: seconds,
            size: thumbSize,
            transfrom: transfrom,
            timeToleranceBefore: timeToleranceBefore,
            timeToleranceAfter: timeToleranceAfter
        )

        if items.isEmpty {
            return []
        }

        return try await encodeThumbnails(
            items,
            for: requests,
            settings: settings,
            crop: crop,
            shouldResize: shouldResize
        )
    }

    /// Edits and writes already-decoded thumbnails.
    ///
    /// Deliberately `nonisolated`: `thumbnailFiles` inherits the caller's
    /// isolation for the sake of the non-`Sendable` `AVAsset`, and this is the
    /// expensive part — vImage/CIImage editing plus a file write per frame.
    /// Running it on a caller's `@MainActor` would stall their UI. Every value
    /// crossing the hop is `Sendable`.
    ///
    /// `@concurrent` makes that hop explicit rather than relying on the current
    /// default. Under the `NonisolatedNonsendingByDefault` upcoming feature — the
    /// Swift 7 default — a plain `nonisolated async` function runs on the
    /// caller's executor, which would silently move all of this back onto the
    /// caller's actor. Verified both ways; the attribute is Swift 6.2+, hence
    /// the guard.
    #if compiler(>=6.2)
    @concurrent
    #endif
    private static func encodeThumbnails(
        _ items: [VideoThumbnail],
        for requests: [VideoThumbnailRequest],
        settings: ImageSettings,
        crop: Crop?,
        shouldResize: Bool
    ) async throws -> [VideoThumbnailFile] {
        // `CImage` variables
        lazy var context = CIContext(options: [.highQualityDownsample: true])
        // `vImage` variables
        var format: vImage_CGImageFormat?
        var tempBuffer: TemporaryBuffer?
        var converterIn: vImageConverter?, converterOut: vImageConverter?

        var thumbnails: [VideoThumbnailFile] = []
        for item in items {
            // Outside the `do` below, which swallows encode failures with
            // `continue` and would discard a `CancellationError` too.
            try Task.checkCancellation()

            let index = item.requestIndex
            guard requests.indices.contains(index) else { continue }
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

        // The loop checks before each frame, and there is no frame after the
        // last one, so cancellation arriving while the final image is being
        // edited or written would otherwise be reported as success. Checked
        // ahead of the emptiness guard as well, so a cancelled run cannot
        // surface as a generation failure.
        try Task.checkCancellation()

        guard !thumbnails.isEmpty else {
            throw CompressionError.failedToGenerateThumbnails
        }
        return thumbnails
    }
}

private func isValidThumbnailTolerance(_ value: Double) -> Bool {
    value == .infinity || (value.isFinite && value >= 0)
}

private func thumbnailToleranceFits(_ value: Double, maximumSeconds: Double) -> Bool {
    value == .infinity || value <= maximumSeconds
}

/// Synchronizes callbacks from `AVAssetImageGenerator`.
internal final class VideoThumbnailCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let requestedTimes: [CMTime]
    private let completion: @Sendable ([VideoThumbnail]) -> Void
    private var remainingCount: Int
    private var received: [Bool]
    private var thumbnails: [VideoThumbnail?]
    private var completed = false

    init(requestedTimes: [CMTime], completion: @escaping @Sendable ([VideoThumbnail]) -> Void) {
        self.requestedTimes = requestedTimes
        remainingCount = requestedTimes.count
        received = Array(repeating: false, count: requestedTimes.count)
        thumbnails = Array(repeating: nil, count: requestedTimes.count)
        self.completion = completion
    }

    func receive(image: CGImage?, requestedTime: CMTime, actualTime: Double) {
        let result: [VideoThumbnail]?

        lock.lock()
        let matchingIndex = requestedTimes.indices.first {
            !received[$0] && CMTimeCompare(requestedTimes[$0], requestedTime) == 0
        } ?? received.indices.first { !received[$0] }

        if let matchingIndex {
            received[matchingIndex] = true
            if let image {
                thumbnails[matchingIndex] =
                VideoThumbnail(
                    image: image,
                    requestedTime: requestedTime.seconds,
                    actualTime: actualTime,
                    requestIndex: matchingIndex
                )
            }
        }
        remainingCount -= 1

        if !completed && remainingCount <= 0 {
            completed = true
            result = thumbnails.compactMap { $0 }
        } else {
            result = nil
        }
        lock.unlock()

        if let result {
            completion(result)
        }
    }
}
