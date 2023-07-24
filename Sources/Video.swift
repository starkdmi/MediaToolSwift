import AVFoundation
import Foundation
import CoreMedia
import CoreImage
import VideoToolbox

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Video related singletone interface
public struct VideoTool {

    /// Compress video file
    /// - Parameters:
    ///   - source: Input video URL
    ///   - destination: Output video URL
    ///   - fileType: Video file contrainer type: MPEG-4, QuickTime and iTunes
    ///   - videoSettings: Video related settings including
    ///      - codec: Video codec used by encoder: H.264, H.265/HEVC, ProRes and JPEG
    ///      - bitrate: Output video bitrate, used only by H.264 and H.265/HEVC codecs
    ///      - quality: Video quality in rage from 0.0 to 1.0, ignored while bitrate is set 
    ///      - size: Video size to fit, original size used when not specified
    ///      - frameRate: Frame rate of output video 
    ///      - preserveAlphaChannel: Can be used to drop alpha channel from video file with transparency 
    ///      - profile: Profile used by video encoder
    ///      - color: Color primaries
    ///      - maxKeyFrameInterval: Maximum interval between keyframes
    ///      - hardwareAcceleration: Hardware acceleration option, macOS only, enabled by default
    ///      - edit: Video related operations - cut, rotate, crop, atd.
    ///   - optimizeForNetworkUse: Allows video file to be streamed over network
    ///   - skipAudio: Disable audio, output file will be muted
    ///   - audioSettings: Audio related settings including
    ///      - codec: Audio codec used by encoder: AAC, Opus, FLAC, Linear PCM, Apple Lossless Audio Codec
    ///      - bitrate: Audio bitrate, used by aac and opus codecs only
    ///      - quality: Audio quality, AAC and FLAC only: low, medium, high
    ///      - sampleRate: Sample rate in Hz
    ///   - skipSourceMetadata: Skip source video file metadata including timed metadata track and asset metadata
    ///   - customMetadata: Provide custom metadata to be added to asset metadata, ignores `skipSourceMetadata`
    ///   - copyExtendedFileMetadata: Copy extended file system metadata tags used for media from source
    ///   - cacheDirectory: Directory for AVAssetWriter to save temporary files before copying to destination
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on success 
    ///   - callback: Compression process state notifier, including error handling and completion
    /// - Returns: Task with option to control the compression process
    public static func convert(
        source: URL,
        destination: URL,
        fileType: CompressionFileType = .mov,
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
        callback: @escaping (CompressionState) -> Void
    ) async -> CompressionTask {
        let task = CompressionTask()

        // Check source file existence
        if !FileManager.default.fileExists(atPath: source.path) {
            // Also caused by insufficient permissions
            callback(.failed(CompressionError.sourceFileNotFound))
            return task
        }

        // Check destination file existence and overwrite setting
        let destinationExists: Bool = FileManager.default.fileExists(atPath: destination.path)
        if destinationExists, !overwrite {
            callback(.failed(CompressionError.destinationFileExists))
            return task
        }

        let asset = AVAsset(url: source)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            callback(.failed(error))
            return task
        }

        // Confirm the file type is set to correct value by comparing with destination file extension
        if destination.pathExtension.lowercased() != fileType.rawValue {
            callback(.failed(CompressionError.invalidFileType))
            return task
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: fileType.value)
        } catch let error {
            callback(.failed(error))
            return task
        }

        // Running in Xcode project do not leave temp file, but swift cmd will store temp file near source after compression
        if let directoryForTemporaryFiles = cacheDirectory {
            writer.directoryForTemporaryFiles = directoryForTemporaryFiles // URL(fileURLWithPath: "/tmp")
        }

        // MARK: Video 

        var videoVariables: VideoVariables!
        do {
            videoVariables = try await initVideo(asset: asset, videoSettings: videoSettings)
        } catch let error {
            callback(.failed(error))
            return task
        }

        // By skipping `shouldOptimizeForNetworkUse` temp file may not be created by `AVAssetWriter`
        writer.shouldOptimizeForNetworkUse = optimizeForNetworkUse

        // Frame rate
        if let frameRate = videoVariables.frameRate {
            writer.movieTimeScale = CMTimeScale(Int32(frameRate))
        }

        // Append video to reader
        guard reader.canAdd(videoVariables.videoOutput) else {
            // To get more info about initialization problem can be called in ObjC exception catcher
            callback(.failed(CompressionError.failedToReadVideo))
            return task
        }
        reader.add(videoVariables.videoOutput)
        /*do {
            try ObjCExceptionCatcher.catchException {
                reader.add(videoVariables.videoOutput)
            }
        } catch let error {
            callback(.failed(error))
            return task
        }*/

        // Append video to writer
        guard writer.canAdd(videoVariables.videoInput) else {
            callback(.failed(CompressionError.failedToWriteVideo))
            return task
        }
        writer.add(videoVariables.videoInput)

        // MARK: Audio

        var audioVariables: AudioVariables!
        if skipAudio {
            audioVariables = AudioVariables()
            audioVariables.skipAudio = true

            if videoVariables.hasChanges == false {
                // Additionally load audio track to check if source file has audio 
                audioVariables.audioTrack = await asset.getFirstTrack(withMediaType: .audio)
                audioVariables.hasChanges = audioVariables.audioTrack != nil
            }
        } else {
            do {
                audioVariables = try await initAudio(asset: asset, audioSettings: audioSettings)
            } catch let error {
                callback(.failed(error))
                return task
            }
        }

        // Prevent the compression when video and audio settings are same as the source file
        if !videoVariables.hasChanges, !audioVariables.hasChanges {
            callback(.failed(CompressionError.redunantCompression))
            return task
        }

        if !audioVariables.skipAudio {
            // Append audio to reader
            guard reader.canAdd(audioVariables.audioOutput!) else {
                callback(.failed(CompressionError.failedToReadAudio))
                return task
            }
            reader.add(audioVariables.audioOutput!)

            // Append audio to writer
            guard writer.canAdd(audioVariables.audioInput!) else {
                callback(.failed(CompressionError.failedToWriteAudio))
                return task
            }
            writer.add(audioVariables.audioInput!)
        }

        // MARK: Metadata

        var metadataVariables = await initMetadata(asset: asset, skipSourceMetadata: skipSourceMetadata, customMetadata: customMetadata)

        if metadataVariables.hasMetadata {
            // Append metadata to reader
            guard reader.canAdd(metadataVariables.metadataOutput!) else {
                callback(.failed(CompressionError.failedToReadMetadata))
                return task
            }
            reader.add(metadataVariables.metadataOutput!)

            // Append metadata to writer
            if writer.canAdd(metadataVariables.metadataInput!) {
                writer.add(metadataVariables.metadataInput!)
            } else {
                // Metadata track will not be added, while metadata still could be set via [writer.metadata]
                metadataVariables.hasMetadata = false
            }
        }

        // Insert source file and custom metadata
        writer.metadata = metadataVariables.metadata

        // MARK: Compression

        // Delete file at destination path
        if destinationExists {
            try? FileManager.default.removeItem(at: destination)
        }

        // Initiate read-write process
        if let timeRange = videoVariables.range {
            // Cut movie - read only required part of clip
            reader.timeRange = timeRange
        }
        reader.startReading()
        writer.startWriting()
        if let timeRange = videoVariables.range {
            // Cut movie - start writing from specified point
            writer.startSession(atSourceTime: timeRange.start)
        } else {
            writer.startSession(atSourceTime: .zero)
        }

        // Notify caller
        callback(.started)

        // Progress related variables
        let progress = Progress(totalUnitCount: videoVariables.totalFrames)
        var frames = 0 // amound of proceed frames

        let group = DispatchGroup()
        var success = 0 // amount of completed operations
        var processes = 0 // amount of operations to be done
        var error: Error? // reading/writing failure

        func run(
            input: AVAssetWriterInput,
            output: AVAssetReaderOutput,
            queue: DispatchQueue,
            sampleHandler: ((CMSampleBuffer) -> Void)? = nil
        ) {
            group.enter()
            processes += 1
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData, !task.isCancelled {
                    // Read
                    guard let sample = output.copyNextSampleBuffer() else {
                        if reader.status == .failed {
                            // Reader fails
                            error = reader.error
                        } else {
                            success += 1
                        }

                        // Complete
                        input.markAsFinished()
                        group.leave()
                        return
                    }

                    // Write
                    if let handler = sampleHandler {
                        handler(sample)
                    } else if !input.append(sample), writer.status == .failed {
                        // Writing fails
                        error = writer.error
                        input.markAsFinished()
                        group.leave()
                        return
                    }

                    // Progress
                    if input.mediaType == .video {
                        frames += 1
                        progress.completedUnitCount = Int64(frames)
                        callback(.progress(progress))
                    }
                }

                if task.isCancelled {
                    // Cancelled
                    input.markAsFinished()
                    group.leave()
                }
            }
        }

        // Video
        let videoQueue = DispatchQueue(label: "MediaToolSwift.video.queue")
        run(input: videoVariables.videoInput, output: videoVariables.videoOutput, queue: videoQueue, sampleHandler: videoVariables.sampleHandler)

        // Audio 
        if !audioVariables.skipAudio {
            let audioQueue = DispatchQueue(label: "MediaToolSwift.audio.queue")
            run(input: audioVariables.audioInput!, output: audioVariables.audioOutput!, queue: audioQueue)
        }

        // Metadata 
        if metadataVariables.hasMetadata {
            let metadataQueue = DispatchQueue(label: "MediaToolSwift.metadata.queue")
            run(input: metadataVariables.metadataInput!, output: metadataVariables.metadataOutput!, queue: metadataQueue)
        }

        let completionQueue = DispatchQueue(label: "MediaToolSwift.completion.queue")
        group.notify(queue: completionQueue) {
            if let error = error {
                // Error in reading/writing process
                reader.cancelReading()
                writer.cancelWriting()
                callback(.failed(error))
            } else if !task.isCancelled || success == processes {
                // Confirm the progress is 1.0
                if progress.completedUnitCount != frames {
                    progress.completedUnitCount = Int64(frames)
                    callback(.progress(progress))
                }

                // Wasn't cancelled and reached OR all operation was completed
                reader.cancelReading()
                writer.finishWriting(completionHandler: {
                    // Extended file metadata
                    FileExtendedAttributes.setExtendedMetadata(
                        source: source,
                        destination: destination,
                        copy: copyExtendedFileMetadata,
                        fileType: fileType
                    )

                    if deleteSourceFile, source.path != destination.path {
                        // Delete input video file
                        try? FileManager.default.removeItem(at: source)
                    }

                    // Finish
                    callback(.completed(writer.outputURL))
                })
            } else { // Cancelled            
                // Wait for sample in progress to complete, 0.5 sec is more than enough
                usleep(500_000)

                // This method should not be called concurrently with any calls to `output.copyNextSampleBuffer()`
                // The documentation of that is unclear - https://developer.apple.com/documentation/avfoundation/avassetreader/1390258-cancelreading
                reader.cancelReading()

                // This method also should not be called concurrently with `input.append()`
                writer.cancelWriting()
                callback(.cancelled)
            }
        }

        return task
    }

    /// Initialize track, reader and writer for video 
    private static func initVideo(asset: AVAsset, videoSettings: CompressionVideoSettings) async throws -> VideoVariables {
        var variables = VideoVariables()

        // Get first video track, an error is raised if none found 
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        // MARK: Reader
        let durationInSeconds = asset.duration.seconds
        let nominalFrameRate = videoTrack.nominalFrameRate
        let naturalTimeScale = await videoTrack.getVideoTimeScale()
        let totalFrames = Int64(ceil(durationInSeconds * Double(nominalFrameRate)))
        // ffmpeg command to get frames amount:
        // ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -print_format csv video.mp4

        // Video codec
        // swiftlint:disable:next force_cast
        let videoDesc = videoTrack.formatDescriptions.first as! CMFormatDescription
        let hasAlphaChannel = videoDesc.hasAlphaChannel
        var sourceVideoCodec = videoDesc.videoCodec
        if sourceVideoCodec == .hevc, hasAlphaChannel {
            // Fix muxa video codec
            sourceVideoCodec = .hevcWithAlpha
        }
        var videoCodec = videoSettings.codec
        if videoCodec == nil {
            // Verify source video codec is valid for output
            let supportedVideoCodecs: [AVVideoCodecType] = [
                .hevc, .hevcWithAlpha,
                .h264,
                .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy, .proRes4444,
                .jpeg
            ]
            guard supportedVideoCodecs.contains(sourceVideoCodec) else {
                throw CompressionError.invalidVideoCodec
            }

            // Use source video codec
            videoCodec = sourceVideoCodec
        }

        // Enable non-default video decoders if required by input video file format
        #if os(OSX)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(videoDesc)
        // let mediaSubTypeString = NSFileTypeForHFSTypeCode(mediaSubType)
        switch mediaSubType {
        case kCMVideoCodecType_VP9:
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        case kCMVideoCodecType_AV1:
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)
        default:
            break
        }
        #endif

        // HDR videos can't have an alpha channel
        var preserveAlphaChannel = videoSettings.preserveAlphaChannel
        let isHDR = videoDesc.isHDRVideo // videoTrack.hasMediaCharacteristic(.containsHDRVideo)
        if preserveAlphaChannel, isHDR {
            preserveAlphaChannel = false
        }

        // Fix the codec based on alpha support option
        // h264 do not support alpha channel, while all prores profiles do
        // hevc has two different codec variants
        if preserveAlphaChannel {
            if hasAlphaChannel {
                // Fix codec, only .hevcWithAlpha and .proRes4444 support alpha channel
                switch videoCodec! {
                case .hevc:
                    videoCodec = .hevcWithAlpha
                case .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy:
                    videoCodec = .proRes4444
                default:
                    break
                }
            } else {
                // Video has no alpha data
                preserveAlphaChannel = false
            }
        } else {
            // Do not store alpha
            if videoCodec == .hevcWithAlpha {
                videoCodec = .hevc
            }
        }

        var videoReaderSettings: [String: Any] = [
            // Pixel format
            kCVPixelBufferPixelFormatTypeKey as String:
                preserveAlphaChannel ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_422YpCbCr8
        ]

        // MARK: Writer
        // Resize (no upscaling applied)
        var videoSize = videoTrack.naturalSize
        let sourceVideoSize = videoSize
        if let size = videoSettings.size, videoSize.width > size.width || videoSize.height > size.height {
            let rect = AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: CGPoint.zero, size: size))
            videoSize = rect.size
        }

        // Video settings
        var videoCompressionSettings: [String: Any] = [:]

        // Adjust Bitrate
        variables.frameRate = videoSettings.frameRate
        if videoCodec == .h264 || videoCodec == .hevc || videoCodec == .hevcWithAlpha {
            // Setting bitrate for jpeg and prores codecs is not allowed
            switch videoSettings.bitrate {
            case .value(let value):
                videoCompressionSettings[AVVideoAverageBitRateKey] = value
            case .auto:
                var codecMultiplier: Float = 1.0
                if videoCodec == .hevc || videoCodec == .hevcWithAlpha {
                    codecMultiplier = 0.5
                } else if videoCodec == .h264 {
                    codecMultiplier = 0.9
                }
                let totalPixels = Float(videoSize.width * videoSize.height)
                let fps = variables.frameRate == nil ? nominalFrameRate : Float(variables.frameRate!)
                let rate = (totalPixels * codecMultiplier * fps) / 8
                videoCompressionSettings[AVVideoAverageBitRateKey] = rate.rounded()
            case .source:
                videoCompressionSettings[AVVideoAverageBitRateKey] = videoTrack.estimatedDataRate.rounded()
            case .encoder:
                break
            }
        }

        // Quality, ignored while bitrate is set
        if let quality = videoSettings.quality {
            videoCompressionSettings[AVVideoQualityKey] = quality
        }

        // Profile Level
        if let profile = videoSettings.profile {
            videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
        }

        // Frame Rate
        if let frameRate = variables.frameRate, Float(frameRate) < nominalFrameRate {
            // Note: The `AVVideoExpectedSourceFrameRateKey` is just a hint to the encoder about the expected source frame rate, and the encoder is free to ignore it
            if videoCodec == .hevc || videoCodec == .hevcWithAlpha {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
            } else if videoCodec == .h264 {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
                #if os(OSX)
                videoCompressionSettings[AVVideoAverageNonDroppableFrameRateKey] = frameRate
                #endif
            }
        } else {
            // Frame rate is nil, greater or equal to source video frame rate
            variables.frameRate = nil
        }

        // Maximum interval between keyframes
        if let maxKeyFrameInterval = videoSettings.maxKeyFrameInterval {
            videoCompressionSettings[AVVideoMaxKeyFrameIntervalKey] = maxKeyFrameInterval
        }

        // Hardware Acceleration
        if videoSettings.hardwareAcceleration == .disabled {
            #if os(OSX)
            // Disable hardware acceleration, may be unsupported using specific codec or device
            videoCompressionSettings[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] = kCFBooleanFalse
            #endif
        }

        var videoParameters: [String: Any] = [
            // https://developer.apple.com/documentation/avfoundation/video_settings
            AVVideoCompressionPropertiesKey: videoCompressionSettings,
            AVVideoCodecKey: videoCodec!,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height
        ]

        // Color Properties 
        if let colorProperties = videoSettings.color {
            // https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/tagging_media_with_video_color_information
            // https://developer.apple.com/library/archive/technotes/tn2227/_index.html
            // https://developer.apple.com/documentation/avfoundation/video_settings/setting_color_properties_for_a_specific_resolution
            /*let colorPrimaries = CMFormatDescriptionGetExtension(videoDesc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
            print("Color Primaries: \(String(describing: colorPrimaries))")*/

            var colorPrimary: String
            var matrix: String
            var transferFunction: String

            switch colorProperties {
            // SD (SMPTE-C)
            case .smpteC:
                colorPrimary = AVVideoColorPrimaries_SMPTE_C
                matrix = AVVideoYCbCrMatrix_ITU_R_601_4
                transferFunction = AVVideoTransferFunction_ITU_R_709_2
            // SD (PAL)
            case .ebu3213:
                #if os(OSX)
                colorPrimary = AVVideoColorPrimaries_EBU_3213
                #else
                // Fallback to iOS and tvOS supported SD color primary
                colorPrimary = AVVideoColorPrimaries_SMPTE_C
                #endif
                matrix = AVVideoYCbCrMatrix_ITU_R_601_4
                transferFunction = AVVideoTransferFunction_ITU_R_709_2
            // HD | P3
            case .p3D65:
                colorPrimary = AVVideoColorPrimaries_P3_D65
                matrix = AVVideoYCbCrMatrix_ITU_R_709_2
                transferFunction = AVVideoTransferFunction_ITU_R_709_2
            // HDTV - ITU-R BT.709
            case .itu709_2:
                colorPrimary = AVVideoColorPrimaries_ITU_R_709_2
                matrix = AVVideoYCbCrMatrix_ITU_R_709_2
                transferFunction = AVVideoTransferFunction_ITU_R_709_2
            // UHDTV - BT.2020
            case .itu2020:
                colorPrimary = AVVideoColorPrimaries_ITU_R_2020
                matrix = AVVideoYCbCrMatrix_ITU_R_2020
                transferFunction = AVVideoTransferFunction_ITU_R_709_2
            case .itu2020_hlg:
                colorPrimary = AVVideoColorPrimaries_ITU_R_2020
                matrix = AVVideoYCbCrMatrix_ITU_R_2020
                transferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            case .itu2020_pq:
                colorPrimary = AVVideoColorPrimaries_ITU_R_2020
                matrix = AVVideoYCbCrMatrix_ITU_R_2020
                transferFunction = AVVideoTransferFunction_SMPTE_ST_2084_PQ
            }

            videoParameters[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorPrimary,
                AVVideoYCbCrMatrixKey: matrix,
                AVVideoTransferFunctionKey: transferFunction
            ]
        }

        // Video operations
        var transform = CGAffineTransform.identity
        var transformed = false // require additional transformation (rotate, flip, mirror, atd.)
        var cropRect: CGRect?
        var imageProcessor: ImageProcessor?
        for operation in videoSettings.edit {
            switch operation {
            case let .cut(from: start, to: end):
                // Apply only one cutting operation, confirm the range is valid
                if variables.range == nil,
                   let range = CMTimeRange(start: start, end: end, duration: durationInSeconds, timescale: naturalTimeScale) {
                    variables.range = range
                }
            case .crop(let options):
                guard videoSettings.size == nil else {
                    throw CompressionError.croppingNotAllowed
                }

                // Get the cropping area
                let naturalSize = videoTrack.naturalSizeWithOrientation
                let rect = options.makeCroppingRectangle(in: naturalSize)
                if rect.origin == .zero && rect.size == naturalSize {
                    // The cropping bounds equal to source video bounds
                    continue
                }
                guard rect.size.width >= 0, rect.size.height >= 0, rect.minX >= 0, rect.minY >= 0,
                       rect.width <= naturalSize.width, rect.height <= naturalSize.height else {
                    // Bounds are out of source video bounds
                    throw CompressionError.croppingOutOfBounds
                }

                // Use crop filter
                cropRect = rect
            case .rotate, .flip, .mirror:
                transform = transform.concatenating(operation.transform!)
                transformed = true
            case .imageProcessing(let function):
                // Video Composition require tranformed video size
                videoSize = videoTrack.naturalSizeWithOrientation

                // Enable video composition
                imageProcessor = function
            }
        }
        let useVideoComposition: Bool = cropRect != nil || imageProcessor != nil
        let videoRect = cropRect ?? CGRect(origin: .zero, size: videoSize)

        // Compare source video settings with output to possibly skip video compression
        let defaultSettings = CompressionVideoSettings()
        if videoCodec == sourceVideoCodec, // output codec equals source video codec
           videoSettings.bitrate == .auto || videoSettings.bitrate == .encoder, // custom bitrate value is not set
           videoSettings.quality == defaultSettings.quality, // quality set to default value
           videoSize == sourceVideoSize, // output size equals source resolution
           variables.frameRate == defaultSettings.frameRate, // output frame rate greater or equals source frame rate
           !(videoSettings.preserveAlphaChannel == false && hasAlphaChannel == true), // false if alpha is removed
           videoSettings.profile?.rawValue == defaultSettings.profile?.rawValue, // profile set to default value
           videoSettings.color == defaultSettings.color, // color set to default value
           videoSettings.maxKeyFrameInterval == defaultSettings.maxKeyFrameInterval, // max ket frame set to default value
           useVideoComposition == false {  // no video composition added

            if variables.range == nil && !transformed { // no video operations applied
                variables.hasChanges = false
            }

            // Lossless Compression can be done even while adjusting frame rate, cutting, rotating, mirroring or flipping the video
            // But disabled for frame rate due to using `Timing Info`, which is not allowed with `nil` outputSettings

            // Set outputSettings to nil to allow lossless compression (no video re-encoding)
            videoReaderSettings = [:]
            videoParameters = [:]
        }

        // Setup video reader, apply crop and overlay if required
        let readerSettings = videoReaderSettings.isEmpty ? nil : videoReaderSettings
        if useVideoComposition {
            let videoComposition = AVMutableVideoComposition(asset: asset) { request in
                //https://developer.apple.com/documentation/coreimage/processing_an_image_using_built-in_filters
                //https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci
                var image = request.sourceImage
                var size = request.renderSize

                // Crop
                if cropRect != nil {
                    image = image.cropped(to: videoRect).transformed(by: CGAffineTransform(translationX: -videoRect.origin.x, y: -videoRect.origin.y))
                    /*let filter = CIFilter(name: "CICrop", parameters: [
                        "inputImage": image,
                        "inputRectangle": CIVector(cgRect: videoRect)
                    ])!
                    image = filter.outputImage!
                    image = image.transformed(by: CGAffineTransform(translationX: -videoRect.origin.x, y: -videoRect.origin.y))*/
                    size = videoRect.size
                }

                // Custom image processor
                if let imageProcessor = imageProcessor {
                    image = imageProcessor(image, size, request.compositionTime.seconds)
                }

                request.finish(with: image, context: nil)
            }

            // Video size (width and height may be swapped - update)
            videoComposition.renderSize = videoRect.size
            videoParameters[AVVideoCodecKey] = videoCodec!
            videoParameters[AVVideoWidthKey] = videoRect.width
            videoParameters[AVVideoHeightKey] = videoRect.height

            // Fix profile (required for HDR content in Video Composition)
            if videoSettings.profile == nil {
                // Video Profile should be adjusted for HDR content support when Video Composition is used
                let bitsPerComponent = videoDesc.bitsPerComponent ?? (isHDR ? 10 : 8)
                if let profile = CompressionVideoProfile.profile(for: videoCodec!, bitsPerComponent: bitsPerComponent) {
                    videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
                    videoParameters[AVVideoCompressionPropertiesKey] = videoCompressionSettings
                }
            }

            // Video reader
            let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: readerSettings)
            videoOutput.videoComposition = videoComposition
            variables.videoOutput = videoOutput
        } else {
            variables.videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        }

        // Video writer
        try ObjCExceptionCatcher.catchException {
            variables.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoParameters.isEmpty ? nil : videoParameters, sourceFormatHint: videoDesc)
        }

        // Transform
        if useVideoComposition {
            variables.videoInput.transform = transform
        } else {
            variables.videoInput.transform = videoTrack.fixedPreferredTransform.concatenating(transform) // videoTrack.preferredTransform
        }

        /// Custom sample buffer handler for video to adjust frame rate
        func makeVideoSampleHandler() -> ((CMSampleBuffer) -> Void)? {
            guard let frameRate = variables.frameRate else { return nil }
            // Frame rate - skip frames and update time stamp & duration of each saved frame
            // Info: Another approach to adjust video frame rate is using AVAssetReaderVideoCompositionOutput
            // Info: It also possible using CMSampleBufferSetOutputPresentationTimeStamp() +- .convertScale(timeScale, method: .quickTime)

            let timeScale = naturalTimeScale
            // Each frame duration - 1.0 multiplied by scale factor
            let frameDuration = CMTimeMake(value: Int64(timeScale) / Int64(frameRate), timescale: timeScale)

            // Find frames which will be written (not skipped)
            let targetFrames = Int(round(Float(totalFrames) * Float(frameRate) / nominalFrameRate))
            var frames: Set<Int> = []
            frames.reserveCapacity(targetFrames)
            // Add first frame index (starting from one)
            frames.insert(1)
            // Find other desired frame indexes
            for index in 1 ..< targetFrames {
                frames.insert(Int(ceil(Double(totalFrames) * Double(index) / Double(targetFrames - 1))))
            }

            var frameIndex: Int = 0
            var previousPresentationTimeStamp: CMTime?

            return { sample in
                frameIndex += 1

                guard frames.contains(frameIndex) else {
                    // Drop current frame
                    return
                }

                // Update frame timing and write
                autoreleasepool {
                    // Get sample timing info
                    var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo()

                    let getTimingInfoStatus = CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timingInfo)
                    // Expect success
                    guard getTimingInfoStatus == noErr else { return }

                    // Set desired frame rate via duration
                    timingInfo.duration = frameDuration

                    // Update the sample timing info
                    if let previousPresentationTimeStamp = previousPresentationTimeStamp {
                        // Calculate the new presentation time stamp
                        timingInfo.presentationTimeStamp = CMTimeAdd(previousPresentationTimeStamp, timingInfo.duration)
                    } else {
                        // First frame
                        if let start = variables.range?.start {
                            timingInfo.presentationTimeStamp = start
                        } else {
                            timingInfo.presentationTimeStamp = CMTime(value: .zero, timescale: timeScale)
                        }
                    }

                    // Update the previous presentation time stamp
                    previousPresentationTimeStamp = timingInfo.presentationTimeStamp

                    // Create a copy of the sample buffer with the new timing info
                    var buffer: CMSampleBuffer!
                    let copySampleBufferStatus = CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: sample,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: &timingInfo,
                        sampleBufferOut: &buffer
                    )

                    if copySampleBufferStatus == noErr {
                        // Append the new sample buffer to the input
                        variables.videoInput.append(buffer)
                    }
                }
            }
        }

        variables.sampleHandler = makeVideoSampleHandler()
        variables.nominalFrameRate = nominalFrameRate
        variables.totalFrames = totalFrames

        return variables
    }

    /// Initialize track, reader and writer for audio 
    private static func initAudio(asset: AVAsset, audioSettings: CompressionAudioSettings?) async throws -> AudioVariables {
        var variables = AudioVariables()

        // Load first audio track if any
        let audioTrack = await asset.getFirstTrack(withMediaType: .audio)
        variables.audioTrack = audioTrack
        if audioTrack == nil {
            variables.skipAudio = true
            variables.hasChanges = false
            return variables
        }
        if audioSettings == nil {
            variables.hasChanges = false
        }

        // MARK: Reader
        var audioReaderSettings: [String: Any]?
        var audioDescription: CMFormatDescription?
        var bitsPerChannel, channelsPerFrame: Int?
        var isFloat, isBigEndian: Bool?
        if !variables.skipAudio {
            // swiftlint:disable:next force_cast
            audioDescription = (audioTrack!.formatDescriptions.first as! CMFormatDescription)

            if let audioSettings = audioSettings {
                // Retvieve source info
                var sampleRate: Int?
                let basicDescription = audioDescription!.audioStreamBasicDescription

                sampleRate = audioSettings.sampleRate ?? Int(basicDescription?.mSampleRate ?? 44100)
                channelsPerFrame = Int(basicDescription?.mChannelsPerFrame ?? 2)

                if let formatFlags = basicDescription?.mFormatFlags {
                    isFloat = formatFlags & kAudioFormatFlagIsFloat != 0
                    isBigEndian = formatFlags & kAudioFormatFlagIsBigEndian != 0
                }

                bitsPerChannel = Int(basicDescription?.mBitsPerChannel ?? 0)
                if bitsPerChannel == nil || bitsPerChannel == 0 {
                    // Calculate bits per channel based on bitrate, channels amount and audio quality
                    let bitrate: Int
                    if case .value(let value) = audioSettings.bitrate {
                        bitrate = value
                    } else {
                        bitrate = 128_000
                    }
                    let quality = (audioSettings.quality ?? .high).rawValue

                    // Formula: bitrate / (8 * channels * quality)
                    let doubleValue: Double = Double(bitrate) / (8 * Double(channelsPerFrame!) * Double(quality))

                    // Limit values in range 0-31
                    let intValue = Int(doubleValue + 0.5) & 0x1F

                    // Find closest divadable by 8 value
                    let remainder = intValue % 8
                    bitsPerChannel = remainder == 0 ? intValue : intValue + (8 - remainder)

                    // Bit depth can only be one of: 8, 16, 24, 32
                    if ![8, 16, 24, 32].contains(bitsPerChannel) {
                        bitsPerChannel = 16
                    }
                }

                // Linear PCM settings for decoder
                audioReaderSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: (sampleRate ?? audioSettings.sampleRate) ?? 44100,
                    AVNumberOfChannelsKey: channelsPerFrame!,
                    AVLinearPCMBitDepthKey: bitsPerChannel!,
                    AVLinearPCMIsFloatKey: isFloat ?? false,
                    AVLinearPCMIsBigEndianKey: isBigEndian ?? false
                ]
            }
        }

        // MARK: Writer
        if !variables.skipAudio {
            let audioFormatID = CMFormatDescriptionGetMediaSubType(audioDescription!)

            var sourceFormatHint: CMFormatDescription?
            var audioParameters: [String: Any]?
            if let audioSettings = audioSettings {
                // Audio settings 
                // https://developer.apple.com/documentation/avfoundation/audio_settings

                var codec = audioSettings.codec
                if codec == .default, let sourceCodec = CompressionAudioCodec(formatId: audioFormatID), sourceCodec != .default {
                    // Use source audio format
                    codec = sourceCodec
                }

                switch codec {
                case .aac:
                    // AAC
                    var channelLayout = AudioChannelLayout()
                    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_2_0 // kAudioChannelLayoutTag_Stereo
                    // let numberOfChannels = channelsPerFrame ?? 2
                    // channelLayout.mChannelLayoutTag = numberOfChannels > 1 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
                    let channelLayoutData = NSData(bytes: &channelLayout, length: MemoryLayout.size(ofValue: channelLayout))
                    audioParameters = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: audioSettings.sampleRate ?? 44100,
                        AVNumberOfChannelsKey: 2, // numberOfChannels
                        AVChannelLayoutKey: channelLayoutData
                        // AVEncoderBitRateKey: audioSettings.bitrate ?? 128_000
                        // AVEncoderAudioQualityKey: (audioSettings.quality ?? .high).rawValue
                    ]
                    if case .value(var bitrate) = audioSettings.bitrate {
                        // Setting wrong bitrate for AAC will crash the execution
                        // MPEG4AAC valid bitrate range is [64, 320]
                        if bitrate < 64000 {
                            bitrate = 64000
                        } else if bitrate > 320_000 {
                            bitrate = 320_000
                        }
                        audioParameters![AVEncoderBitRateKey] = bitrate
                    }
                    if let quality = audioSettings.quality {
                        audioParameters![AVEncoderAudioQualityKey] = quality.rawValue
                    }
                case .opus:
                    // Opus
                    audioParameters = [
                        AVFormatIDKey: kAudioFormatOpus,
                        AVSampleRateKey: audioSettings.sampleRate ?? 48000,
                        AVNumberOfChannelsKey: channelsPerFrame ?? 2
                        // AVEncoderBitRateKey: audioSettings.bitrate ?? 96000
                    ]
                    if case .value(let bitrate) = audioSettings.bitrate {
                        // Invalid bitrate will not break the execution for Opus
                        // Fallback to range [2, 510] is done automatically
                        audioParameters![AVEncoderBitRateKey] = bitrate
                    }
                case .flac:
                    // Flac
                    audioParameters = [
                        AVFormatIDKey: kAudioFormatFLAC,
                        AVSampleRateKey: audioSettings.sampleRate ?? 44100,
                        AVNumberOfChannelsKey: channelsPerFrame ?? 2
                    ]
                    if let quality = audioSettings.quality {
                        audioParameters![AVEncoderAudioQualityKey] = quality.rawValue
                    }
                case .lpcm:
                    // Linear PCM 
                    audioParameters = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: audioSettings.sampleRate ?? 44100,
                        AVNumberOfChannelsKey: channelsPerFrame ?? 2,
                        AVLinearPCMBitDepthKey: bitsPerChannel ?? 16,
                        AVLinearPCMIsFloatKey: isFloat ?? false,
                        AVLinearPCMIsBigEndianKey: isBigEndian ?? false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                case .alac:
                    // Apple Lossless
                    audioParameters = [
                        AVFormatIDKey: kAudioFormatAppleLossless,
                        AVSampleRateKey: audioSettings.sampleRate ?? 44100,
                        AVNumberOfChannelsKey: channelsPerFrame ?? 2,
                        AVEncoderBitDepthHintKey: bitsPerChannel ?? 16
                    ]
                case .default:
                    sourceFormatHint = audioDescription
                    variables.hasChanges = false
                }

                // Compare source audio settings with output to possibly skip the compression
                let defaultSettings = CompressionAudioSettings()
                if audioFormatID == codec.formatId, // output format equals to source audio format
                   audioSettings.bitrate == defaultSettings.bitrate, // default settings is used for bitrate
                   !((audioFormatID == kAudioFormatMPEG4AAC || audioFormatID == kAudioFormatFLAC) && audioSettings.quality != defaultSettings.quality), // default settings is used for quality (aac and flac only)
                   audioSettings.sampleRate == defaultSettings.sampleRate // default settings is used for sample rate
                {
                    // Info: Bitrate is not calculated internally, so providing any value to audio bitrate using `.value(Int)` will require compression, even if .value(135_000) equals to source audio bitrate
                    variables.hasChanges = false
                }
            } else {
                sourceFormatHint = audioDescription
            }

            if !variables.hasChanges {
                // Lossless Compression (no re-encoding required)
                audioReaderSettings = nil
                audioParameters = nil
            }

            variables.audioOutput = AVAssetReaderTrackOutput(track: audioTrack!, outputSettings: audioReaderSettings)

            try ObjCExceptionCatcher.catchException {
                variables.audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioParameters, sourceFormatHint: sourceFormatHint)
            }

            // Adjust Volume 
            /*if let volume = audioSettings?.volume {
                variables.audioInput!.preferredVolume = volume
            }*/
        }

        return variables
    }

    /// Initialize timed metadata track, reader, writer and collect metadata information
    private static func initMetadata(asset: AVAsset, skipSourceMetadata: Bool, customMetadata: [AVMetadataItem]) async -> MetadataVariables {
        var variables = MetadataVariables()

        var hasMetadata = false
        var metadata: [AVMetadataItem] = []
        var metadataTrack: AVAssetTrack?
        if !skipSourceMetadata {
            // Timed Metadata
            metadataTrack = await asset.getFirstTrack(withMediaType: .metadata)
            if metadataTrack != nil {
                hasMetadata = true
            }

            // Collect asset metadata
            metadata.append(contentsOf: await asset.getMetadata())
            // To get all video metadata using ffmpeg use
            // ffprobe -loglevel error -show_entries stream_tags:format_tags -of json video.mp4
        }

        // MARK: Reader
        if hasMetadata {
            variables.metadataOutput = AVAssetReaderTrackOutput(track: metadataTrack!, outputSettings: nil)
        }

        // MARK: Writer
        if hasMetadata {
            // swiftlint:disable:next force_cast
            let metadataDesc = metadataTrack!.formatDescriptions.first as! CMFormatDescription
            do {
                try ObjCExceptionCatcher.catchException {
                    variables.metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metadataDesc)
                }
            } catch {
                // Metadata track will not be added, while metadata still could be set via [writer.metadata]
                hasMetadata = false
            }
        }

        // Append custom metadata
        metadata.append(contentsOf: customMetadata)

        variables.hasMetadata = hasMetadata
        variables.metadata = metadata

        return variables
    }

    // MARK: Video Thumbnail

    /// Generate multiple CGImage thumbnails
    /// - Parameters:
    ///     - asset: Input video asset
    ///     - seconds: Array of points in seconds to generate thumbnails at, can differ based on tolerance
    ///     - size: Thumbnail size to fit in
    ///     - transfrom: Apply preferred source video tranformations if `true`
    ///     - timeToleranceBefore: Time tolerance before specified time, in seconds
    ///     - timeToleranceBefore: Time tolerance after specified time, in seconds
    /// - Returns: Array of image thumbnail objects
    public static func thumbnailImages(
        for asset: AVAsset,
        at seconds: [Double],
        size: CGSize?,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity
    ) async throws -> [VideoThumbnail] {
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        // Convert seconds to `CMTime`s
        // let timeScale: CMTimeScale = max(600, CMTimeScale(videoTrack.nominalFrameRate))
        var timeScale = CMTimeScale(videoTrack.nominalFrameRate)
        if timeScale < 240 { timeScale = 240 } // 60, 240, 600
        let seconds = seconds.map({ CMTimeMakeWithSeconds($0, preferredTimescale: timeScale) })

        // AVAssetImageGenerator - https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/creating_images_from_a_video_asset
        let generator = AVAssetImageGenerator(asset: asset)

        // Transform video frame
        generator.appliesPreferredTrackTransform = transfrom

        // Size to fit in
        let videoSize = videoTrack.naturalSizeWithOrientation // videoTrack.naturalSize.applying(videoTrack.fixedPreferredTransform)
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

        var thumbnails: [VideoThumbnail] = []
        if #available(macOS 13, iOS 16, tvOS 16, *) {
            for await result in generator.images(for: seconds) {
                let requestedTime = result.requestedTime
                if let image = try? result.image, let actualTime = try? result.actualTime {
                    thumbnails.append(VideoThumbnail(image: image, requestedTime: requestedTime.seconds, actualTime: actualTime.seconds))
                }
            }
        } else {
            await withUnsafeContinuation { continuation in
                let nsSeconds = seconds.map({ NSValue(time: $0) })
                var count = seconds.count
                generator.generateCGImagesAsynchronously(forTimes: nsSeconds, completionHandler: { (requestedTime, image, actualTime, _, _) in
                    if let image = image {
                        thumbnails.append(VideoThumbnail(image: image, requestedTime: requestedTime.seconds, actualTime: actualTime.seconds))
                    }
                    count -= 1
                    if count <= 0 || thumbnails.count == seconds.count {
                        continuation.resume()
                    }
                })
            }
        }

        return thumbnails
    }

    /// Generate multiple file thumbnails
    /// - Parameters:
    ///     - asset: Input video asset
    ///     - requests: Array of points in seconds to generate thumbnails at and url to save file at
    ///     - settings: Output images settings
    ///     - transfrom: Apply preferred source video tranformations if `true`
    ///     - timeToleranceBefore: Time tolerance before specified time, in seconds
    ///     - timeToleranceBefore: Time tolerance after specified time, in seconds
    /// - Returns: Array of file thumbnail objects
    public static func thumbnailFiles(
        of asset: AVAsset,
        at requests: [VideoThumbnailRequest],
        settings: ImageSettings,
        transfrom: Bool = true,
        timeToleranceBefore: Double = .infinity,
        timeToleranceAfter: Double = .infinity
    ) async throws -> [VideoThumbnailFile] {
        var thumbSize = settings.size

        // Calculate max size based on Crop, Rotate and Resize operations
        // And request lower resolution thumbnail even before applying them
        if !settings.edit.isEmpty, let videoTrack = await asset.getFirstTrack(withMediaType: .video) {
            // Video size
            var videoRect = CGRect(origin: .zero, size: videoTrack.naturalSizeWithOrientation)
            if let resize = settings.size {
                videoRect = AVMakeRect(aspectRatio: videoRect.size, insideRect: CGRect(origin: CGPoint.zero, size: resize))
            }

            // Temp image
            var ciImage = CIImage(color: .black).cropped(to: videoRect)

            // Apply operations in sorted order
            for operation in settings.edit.sorted() {
                switch operation {
                case .crop(let options):
                    let rect = options.makeCroppingRectangle(in: videoRect.size)
                    ciImage = ciImage.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
                case .rotate(let value):
                    ciImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: value.radians))
                /*case .imageProcessing(let function):
                    ciImage = function(ciImage)*/
                default:
                    // Unnecessary for the size calculation operations
                    break
                }
            }

            // Final max size of an image after operations applied
            thumbSize = CGSize(width: ciImage.extent.origin.x + ciImage.extent.size.width, height: ciImage.extent.origin.y + ciImage.extent.size.height)
        }

        // Request the images at specific times
        let seconds = requests.map({ $0.time })
        let items = try await thumbnailImages(for: asset, at: seconds, size: thumbSize, transfrom: transfrom, timeToleranceBefore: timeToleranceBefore, timeToleranceAfter: timeToleranceAfter)
        guard items.count > 0 else { return [] }

        var thumbnails: [VideoThumbnailFile] = []
        // Save image in options.format applying options
        for index in 0...items.count-1 {
            do {
                let item = items[index]
                var image = item.image
                let url = requests[index].url

                // Edit
                if !settings.edit.isEmpty {
                    image = image.edit(settings: settings)
                }

                // Write an image
                let frames = [ImageFrame(image: image)]
                try ImageTool.saveImage(frames, at: url, settings: settings)

                // Add to success array
                thumbnails.append(VideoThumbnailFile(url: url, format: settings.format, size: CGSize(width: image.width, height: image.height), time: item.actualTime))
            } catch { } // skip
        }

        return thumbnails
    }
}
