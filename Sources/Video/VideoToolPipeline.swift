import AVFoundation
import CoreImage
import VideoToolbox

#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

// MARK: - Video Initialization

extension VideoTool {

    /// Initializes the video track, reader output, and writer input.
    internal static func initializeVideo(
        asset: AVAsset,
        videoSettings: CompressionVideoSettings
    ) async throws -> VideoVariables {
        var variables = VideoVariables()

        // Get first video track
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        // MARK: - Phase 1: Analyze Source Track

        let trackAnalyzer = VideoTrackAnalyzer()
        let analysis = try await trackAnalyzer.analyze(track: videoTrack, asset: asset)

        // Register supplemental decoders if needed (VP9, AV1 on macOS)
        trackAnalyzer.registerSupplementalDecodersIfNeeded(for: analysis.formatDescription)

        var totalFrames = analysis.totalFrames
        let durationInSeconds = analysis.duration.seconds

        // MARK: - Phase 2: Resolve Output Codec

        let codecResolver = VideoCodecResolver()
        let codecResolution = try codecResolver.resolve(
            requestedCodec: videoSettings.codec,
            sourceCodec: analysis.codec,
            sourceHasAlpha: analysis.hasAlpha,
            isHDR: analysis.isHDR,
            preserveAlphaRequested: videoSettings.preserveAlphaChannel
        )

        variables.codec = codecResolution.codec
        variables.hasAlpha = codecResolution.hasAlpha
        variables.isHDR = analysis.isHDR
        variables.orientation = analysis.orientation
        variables.sourceDuration = analysis.duration

        // MARK: - Phase 3: Process Video Operations

        var transform = CGAffineTransform.identity
        var transformed = false
        var cropRect: CGRect?
        var cutDurationInSeconds: Double?
        var frameProcessor: VideoFrameProcessor?

        for operation in videoSettings.edit {
            switch operation {
            case let .cut(from: start, to: end):
                if variables.range == nil,
                   let range = CMTimeRange(start: start, end: end, duration: durationInSeconds, timescale: analysis.timeScale) {
                    variables.range = range
                    cutDurationInSeconds = range.duration.seconds
                    totalFrames = Int64(ceil(cutDurationInSeconds! * Double(analysis.nominalFrameRate)))
                }
            case .crop(let options):
                let rect = options.makeCroppingRectangle(in: analysis.sourceVideoSize)
                if rect.origin == .zero && rect.size == analysis.sourceVideoSize {
                    continue
                }
                guard rect.size.width >= 0, rect.size.height >= 0, rect.minX >= 0, rect.minY >= 0,
                      rect.width <= analysis.sourceVideoSize.width, rect.height <= analysis.sourceVideoSize.height else {
                    throw CompressionError.croppingOutOfBounds
                }
                cropRect = rect
            case .rotate, .flip, .mirror:
                transform = transform.concatenating(operation.transform!)
                transformed = true
            case .process(let processor):
                frameProcessor = processor
            }
        }

        // MARK: - Phase 4: Calculate Output Size

        let sizeCalculator = VideoSizeCalculator()
        let sizeResult = try sizeCalculator.calculate(
            settings: videoSettings.size,
            sourceSize: analysis.sourceVideoSize,
            operations: videoSettings.edit,
            orientation: analysis.orientation
        )

        var targetVideoSize = sizeResult.targetSize
        let videoSize = sizeResult.resolvedSizeOption
        // Prefer sizeResult.cropRect since sizeCalculator already validated bounds
        // Fall back to locally parsed cropRect if sizeResult doesn't have it
        let effectiveCropRect = sizeResult.cropRect ?? cropRect

        let useVideoAdaptor = frameProcessor?.requirePixelAdaptor == true
        var useVideoComposition = frameProcessor?.canCrop != true && effectiveCropRect != nil

        #if os(visionOS)
        if useVideoComposition {
            throw CompressionError.notSupportedOnVisionOS
        }
        #else
        if case .imageComposition = frameProcessor {
            useVideoComposition = true
        }
        #endif

        // Video Composition requires transformed video size
        if !useVideoComposition {
            targetVideoSize = targetVideoSize.oriented(analysis.orientation)
        }

        // MARK: - Phase 5: Calculate Bitrate

        let bitrateCalculator = VideoBitrateCalculator()
        let effectiveFrameRate = videoSettings.frameRate.map { Float($0) } ?? analysis.nominalFrameRate
        let bitrateResult = bitrateCalculator.calculate(
            bitrateOption: videoSettings.bitrate,
            sourceBitrate: analysis.estimatedDataRate,
            targetSize: targetVideoSize,
            sourceSize: analysis.naturalSize,
            codec: codecResolution.codec,
            codecChanged: codecResolution.codecChanged,
            isHDR: analysis.isHDR,
            frameRate: effectiveFrameRate,
            duration: cutDurationInSeconds ?? durationInSeconds
        )

        variables.bitrate = bitrateResult.targetBitrate
        variables.estimatedFileLength = bitrateResult.estimatedFileSizeKB
        variables.isEstimatedFileSizeAccurate = bitrateResult.isEstimatedFileSizeAccurate

        // MARK: - Phase 6: Build Compression Settings

        var videoCompressionSettings: [String: Any] = [:]

        // Quality
        if let quality = videoSettings.quality {
            videoCompressionSettings[AVVideoQualityKey] = quality
        }

        // Profile
        if let profile = videoSettings.profile {
            videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
        }

        // Frame Rate
        variables.frameRate = videoSettings.frameRate
        if let frameRate = variables.frameRate, Float(frameRate) < analysis.nominalFrameRate {
            if codecResolution.codec == .hevc || codecResolution.codec == .hevcWithAlpha {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
            } else if codecResolution.codec == .h264 {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
                #if os(macOS)
                videoCompressionSettings[AVVideoAverageNonDroppableFrameRateKey] = frameRate
                #endif
            }
        } else {
            variables.frameRate = nil
        }

        // Max key frame interval
        if let maxKeyFrameInterval = videoSettings.maxKeyFrameInterval {
            videoCompressionSettings[AVVideoMaxKeyFrameIntervalKey] = maxKeyFrameInterval
        }

        // Hardware acceleration
        if videoSettings.hardwareAcceleration == .disabled {
            #if os(macOS)
            videoCompressionSettings[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] = kCFBooleanFalse
            #endif
        }

        // On current SDKs, make the public preserve-alpha setting explicit.
        // Without this, ProRes 4444 can retain an opaque alpha plane even when
        // the caller asked to discard alpha data.
        #if !os(visionOS)
        if codecResolution.codec == .proRes4444,
           #available(macOS 13, iOS 16, tvOS 16, *) {
            videoCompressionSettings[kVTCompressionPropertyKey_PreserveAlphaChannel as String] = codecResolution.preserveAlpha
        }
        #endif

        // Apply bitrate
        if let bitrateValue = bitrateResult.targetBitrate {
            videoCompressionSettings[AVVideoAverageBitRateKey] = bitrateValue
        }

        // Build video parameters
        var videoParameters: [String: Any] = [
            AVVideoCodecKey: codecResolution.codec
        ]

        // Color information
        var colorInfo: VideoColorInformation?
        if let colorProperties = videoSettings.color {
            colorInfo = VideoColorInformation(for: colorProperties)
        } else if let colorPrimaries = analysis.colorPrimaries,
                  let matrix = analysis.colorMatrix,
                  let transferFunction = analysis.colorTransferFunction {
            colorInfo = VideoColorInformation(colorPrimaries: colorPrimaries, matrix: matrix, transferFunction: transferFunction)
        }
        if let colorInfo = colorInfo {
            videoParameters[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorInfo.colorPrimaries,
                AVVideoYCbCrMatrixKey: colorInfo.matrix,
                AVVideoTransferFunctionKey: colorInfo.transferFunction
            ]
        }

        // Set final resolution
        videoParameters[AVVideoWidthKey] = targetVideoSize.width
        videoParameters[AVVideoHeightKey] = targetVideoSize.height
        videoParameters[AVVideoCompressionPropertiesKey] = videoCompressionSettings

        // MARK: - Phase 7: Check for Passthrough (No Changes)

        let defaultSettings = CompressionVideoSettings()
        if codecResolution.codecChanged == false,
           bitrateResult.bitrateChanged == false,
           videoSettings.quality == defaultSettings.quality,
           targetVideoSize == analysis.naturalSize,
           variables.frameRate == defaultSettings.frameRate,
           !(videoSettings.preserveAlphaChannel == false && analysis.hasAlpha == true),
           videoSettings.profile?.rawValue == defaultSettings.profile?.rawValue,
           videoSettings.color == defaultSettings.color,
           videoSettings.maxKeyFrameInterval == defaultSettings.maxKeyFrameInterval,
           frameProcessor == nil,
           useVideoComposition == false {
            if variables.range == nil && !transformed {
                variables.hasChanges = false
            }
        }

        // MARK: - Phase 8: Setup Reader/Writer

        let pixelFormat = !codecResolution.preserveAlpha && frameProcessor == nil
            ? kCVPixelFormatType_422YpCbCr8
            : kCVPixelFormatType_32BGRA

        var videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]

        // If no changes, use passthrough mode
        if !variables.hasChanges {
            videoReaderSettings = [:]
            videoParameters = [:]
        }

        // Setup video reader
        let readerSettings = videoReaderSettings.isEmpty ? nil : videoReaderSettings

        // Context for reuse
        var context: CIContext?
        if frameProcessor?.requireCIContext == true || useVideoComposition {
            context = CIContext(options: [.highQualityDownsample: true])
        }

        #if os(visionOS)
        variables.videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        #else
        if useVideoComposition {
            // Use video composition for crop/overlay/processing
            let videoComposition = buildVideoComposition(
                asset: asset,
                videoTrack: videoTrack,
                cropRect: effectiveCropRect,
                videoSize: videoSize,
                targetVideoSize: targetVideoSize,
                frameProcessor: frameProcessor,
                colorInfo: colorInfo,
                context: context,
                orientation: analysis.orientation
            )

            // Fix profile (required for HDR content in Video Composition)
            // Original applies this for ALL video compositions, not just HDR
            // Uses bitsPerComponent to determine appropriate profile
            if videoSettings.profile == nil {
                let bitsPerComponent = analysis.bitsPerComponent ?? (analysis.isHDR ? 10 : 8)
                if let profile = CompressionVideoProfile.profile(for: codecResolution.codec, bitsPerComponent: bitsPerComponent) {
                    videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
                    videoParameters[AVVideoCompressionPropertiesKey] = videoCompressionSettings
                }
            }

            let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: readerSettings)
            videoOutput.videoComposition = videoComposition
            variables.videoOutput = videoOutput
        } else {
            variables.videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        }
        #endif

        // Video writer
        try ObjCExceptionCatcher.catchException {
            variables.videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoParameters.isEmpty ? nil : videoParameters,
                sourceFormatHint: analysis.formatDescription
            )

            // Init pixel buffer adaptor
            if useVideoAdaptor {
                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                    kCVPixelBufferWidthKey as String: targetVideoSize.width,
                    kCVPixelBufferHeightKey as String: targetVideoSize.height,
                    AVVideoWidthKey: targetVideoSize.width,
                    AVVideoHeightKey: targetVideoSize.height
                ]
                variables.videoInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: variables.videoInput,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
            }
            return
        }

        // Transform
        if useVideoComposition {
            variables.videoInput.transform = transform
        } else {
            variables.videoInput.transform = analysis.fixedPreferredTransform.concatenating(transform)
        }

        // MARK: - Phase 9: Sample Handler

        variables.sampleHandler = makeSampleHandler(
            frameProcessor: frameProcessor,
            frameRate: variables.frameRate,
            totalFrames: totalFrames,
            nominalFrameRate: analysis.nominalFrameRate,
            timeScale: analysis.timeScale,
            range: variables.range,
            videoSize: videoSize,
            targetVideoSize: targetVideoSize.oriented(analysis.orientation),
            cropRect: effectiveCropRect,
            fixedPreferredTransform: analysis.fixedPreferredTransform,
            videoInputAdaptor: variables.videoInputAdaptor,
            colorInfo: colorInfo,
            context: context,
            orientation: analysis.orientation
        )

        variables.nominalFrameRate = analysis.nominalFrameRate
        variables.totalFrames = totalFrames
        variables.size = targetVideoSize

        return variables
    }

    // MARK: - Helper: Build Video Composition

    #if !os(visionOS)
    private static func buildVideoComposition(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        cropRect: CGRect?,
        videoSize: CompressionVideoSize,
        targetVideoSize: CGSize,
        frameProcessor: VideoFrameProcessor?,
        colorInfo: VideoColorInformation?,
        context: CIContext?,
        orientation: VideoOrientation
    ) -> AVMutableVideoComposition {
        let renderer = VideoCompositionRenderer(
            cropRect: cropRect,
            videoSize: videoSize,
            targetVideoSize: targetVideoSize,
            frameProcessor: frameProcessor,
            context: context
        )
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            renderer.render(request)
        }

        // Calculate render size
        var renderSize: CGSize?
        if frameProcessor == nil {
            renderSize = cropRect?.size
        } else if case .imageComposition = frameProcessor {
            renderSize = targetVideoSize
        } else {
            if case .fit = videoSize {
                renderSize = targetVideoSize
            } else {
                renderSize = cropRect?.size
            }
        }

        if let renderSize = renderSize {
            videoComposition.renderSize = renderSize
        }

        // Set color information
        if let colorInfo = colorInfo {
            videoComposition.colorPrimaries = colorInfo.colorPrimaries
            videoComposition.colorYCbCrMatrix = colorInfo.matrix
            videoComposition.colorTransferFunction = colorInfo.transferFunction
        }

        return videoComposition
    }
    #endif

    // MARK: - Helper: Make Sample Handler

    private static func makeSampleHandler(
        frameProcessor: VideoFrameProcessor?,
        frameRate: Int?,
        totalFrames: Int64,
        nominalFrameRate: Float,
        timeScale: CMTimeScale,
        range: CMTimeRange?,
        videoSize: CompressionVideoSize,
        targetVideoSize: CGSize,
        cropRect: CGRect?,
        fixedPreferredTransform: CGAffineTransform,
        videoInputAdaptor: AVAssetWriterInputPixelBufferAdaptor?,
        colorInfo: VideoColorInformation?,
        context: CIContext?,
        orientation: VideoOrientation
    ) -> ((CMSampleBuffer) -> [CMSampleBuffer])? {
        // Sample writer
        let append: (CMSampleBuffer) -> [CMSampleBuffer] = { sample in
            autoreleasepool {
                switch frameProcessor {
                case .image, .pixelBuffer:
                    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sample)
                    let pixelBuffer = CVPixelBuffer.processSampleBuffer(
                        sample,
                        presentationTimeStamp: timeStamp,
                        processor: frameProcessor!,
                        videoSize: videoSize,
                        targetSize: targetVideoSize,
                        cropRect: cropRect,
                        transform: fixedPreferredTransform,
                        pixelBufferAdaptor: videoInputAdaptor!,
                        colorInfo: colorInfo,
                        context: context
                    )

                    if let pixelBuffer = pixelBuffer {
                        videoInputAdaptor!.append(pixelBuffer, withPresentationTime: timeStamp)
                    }
                    return []
                case .sampleBuffer(let processor):
                    if let sampleBuffer = processor(sample) {
                        return [sampleBuffer]
                    }
                    return []
                default:
                    return [sample]
                }
            }
        }

        guard let frameRate = frameRate else {
            return frameProcessor != nil ? append : nil
        }

        // Frame rate adjustment
        let frameDuration = CMTimeMake(value: Int64(timeScale) / Int64(frameRate), timescale: timeScale)

        let targetFrames = Int(round(Float(totalFrames) * Float(frameRate) / nominalFrameRate))
        var frames: Set<Int> = []
        frames.reserveCapacity(targetFrames)
        frames.insert(1)
        for index in 1 ..< targetFrames {
            frames.insert(Int(ceil(Double(totalFrames) * Double(index) / Double(targetFrames - 1))))
        }

        var frameIndex: Int = 0
        var previousPresentationTimeStamp: CMTime?

        return { sample in
            frameIndex += 1

            guard frames.contains(frameIndex) else {
                return []
            }

            return autoreleasepool { () -> [CMSampleBuffer] in
                var timingInfo = CMSampleTimingInfo()

                let status = CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timingInfo)
                guard status == noErr else { return [] }

                timingInfo.duration = frameDuration

                if let prev = previousPresentationTimeStamp {
                    timingInfo.presentationTimeStamp = CMTimeAdd(prev, timingInfo.duration)
                } else {
                    if let start = range?.start {
                        timingInfo.presentationTimeStamp = start
                    } else {
                        timingInfo.presentationTimeStamp = CMTime(value: .zero, timescale: timeScale)
                    }
                }

                previousPresentationTimeStamp = timingInfo.presentationTimeStamp

                var buffer: CMSampleBuffer!
                let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sample,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timingInfo,
                    sampleBufferOut: &buffer
                )

                if copyStatus == noErr {
                    return append(buffer)
                }
                return []
            }
        }
    }
}

#if !os(visionOS)
/// Serializes stateful Core Image composition processing. AVFoundation may call
/// a composition handler concurrently, while CIFilter, CIContext, and user
/// frame-processor closures must stay confined to one execution context.
private final class VideoCompositionRenderer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MediaToolSwift.video.composition")
    private let cropRect: CGRect?
    private let videoSize: CompressionVideoSize
    private let targetVideoSize: CGSize
    private let frameProcessor: VideoFrameProcessor?
    private let context: CIContext?
    private let scaleFilter: CIFilter?

    init(
        cropRect: CGRect?,
        videoSize: CompressionVideoSize,
        targetVideoSize: CGSize,
        frameProcessor: VideoFrameProcessor?,
        context: CIContext?
    ) {
        self.cropRect = cropRect
        self.videoSize = videoSize
        self.targetVideoSize = targetVideoSize
        self.frameProcessor = frameProcessor
        self.context = context

        switch videoSize {
        case .fit, .scale:
            scaleFilter = CIFilter(name: "CILanczosScaleTransform")
        default:
            scaleFilter = nil
        }
    }

    func render(_ request: AVAsynchronousCIImageFilteringRequest) {
        queue.sync {
            var image = request.sourceImage

            if let cropRect {
                image = image.cropping(to: cropRect)
            }

            guard let frameProcessor else {
                request.finish(with: image, context: context)
                return
            }

            if case .fit = videoSize, let scaleFilter,
               let scaled = image.resizing(to: targetVideoSize, using: scaleFilter) {
                image = scaled
            }

            if case .imageComposition(let imageProcessor) = frameProcessor,
               let context {
                image = imageProcessor(image, context, request.compositionTime.seconds)

                if image.extent.size != targetVideoSize, let scaleFilter,
                   let scaled = image.resizing(to: targetVideoSize, using: scaleFilter) {
                    image = scaled
                }
            }

            request.finish(with: image, context: context)
        }
    }
}
#endif
