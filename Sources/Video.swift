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
        /*guard reader.canAdd(videoVariables.videoOutput) else {
            // To get more info about initialization problem can be called in ObjC exception catcher
            callback(.failed(CompressionError.failedToReadVideo))
            return task
        }
        reader.add(videoVariables.videoOutput)

        // Append video to writer
        guard writer.canAdd(videoVariables.videoInput) else {
            callback(.failed(CompressionError.failedToWriteVideo))
            return task
        }
        writer.add(videoVariables.videoInput)*/

        // Append video to reader and writer with detailed error description
        do {
            try ObjCExceptionCatcher.catchException {
                reader.add(videoVariables.videoOutput)
                writer.add(videoVariables.videoInput)
                return
            }
        } catch let error {
            callback(.failed(error))
            return task
        }

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
            /*guard reader.canAdd(audioVariables.audioOutput!) else {
                callback(.failed(CompressionError.failedToReadAudio))
                return task
            }
            reader.add(audioVariables.audioOutput!)

            // Append audio to writer
            guard writer.canAdd(audioVariables.audioInput!) else {
                callback(.failed(CompressionError.failedToWriteAudio))
                return task
            }
            writer.add(audioVariables.audioInput!)*/

            // Append audio to reader and writer with detailed error description
            do {
                try ObjCExceptionCatcher.catchException {
                    reader.add(audioVariables.audioOutput!)
                    writer.add(audioVariables.audioInput!)
                    return
                }
            } catch let error {
                callback(.failed(error))
                return task
            }
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
        let timeRange = videoVariables.range ?? CMTimeRange(start: .zero, duration: asset.duration)
        let startTime = timeRange.start.value
        let duration = timeRange.duration
        // Calculate frame duration based on source frame rate
        let frameDuration: Int64
        if let nominalFrameRate = videoVariables.nominalFrameRate {
            frameDuration = Int64(duration.timescale / Int32(nominalFrameRate.rounded()))
        } else {
            frameDuration = .zero
        }
        // The progress keeper
        let totalUnitCount = duration.value
        let progress = Progress(totalUnitCount: totalUnitCount)
        let timeStarted = Date() // elapsed and remaining time calculation
        // Percentage offset used before starting the remaining time calculations
        let timeProgressOffset: Double
        switch videoVariables.estimatedFileLength! {
        case 0...10_000: // small file (10MB), 10% offset
            timeProgressOffset = 0.1
        case 10_000...25_000: // medium file (10-25MB), 5% offset
            timeProgressOffset = 0.05
        case 25_000...50_000: // large file (25-50MB), 3% offset
            timeProgressOffset = 0.03
        default: // very big file (>50MB), 1% offset
            timeProgressOffset = 0.01
        }

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
                        // Get current time stamp (proceed asynchronously)
                        let timeStamp = sample.presentationTimeStamp.value
                        // Add frame duration to the starting time stamp
                        let currentTime = timeStamp + frameDuration
                        // Distract cutted out media part at the beginning
                        var completedUnitCount = currentTime - startTime

                        // Progress can overflow a bit (less than `frameDuration` value)
                        completedUnitCount = min(completedUnitCount, totalUnitCount)

                        // Check the current state is maximum, due to async processing
                        if completedUnitCount > progress.completedUnitCount {
                            progress.completedUnitCount = completedUnitCount

                            // Calculate estimated remaining time
                            if let timeRemaining = progress.estimateRemainingTime(
                                startedAt: timeStarted,
                                offset: timeProgressOffset
                            ) {
                                progress.estimatedTimeRemaining = timeRemaining
                            }

                            callback(.progress(encoding: progress, writing: nil))
                        }
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
        run(
            input: videoVariables.videoInput,
            output: videoVariables.videoOutput,
            queue: videoQueue,
            sampleHandler: videoVariables.sampleHandler
        )

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
                if progress.completedUnitCount != totalUnitCount {
                    progress.completedUnitCount = totalUnitCount
                    callback(.progress(encoding: progress, writing: nil))
                }

                // Saving/writing progress
                var observer: FileSizeObserver?
                let estimatedFileLength = Int64(videoVariables.estimatedFileLength! * 1024) // bytes
                let writingProgress = Progress(totalUnitCount: estimatedFileLength)
                writingProgress.kind = .file
                writingProgress.fileURL = destination
                // Skip writing progress for small files due to inaccurate file size estimation
                if videoVariables.estimatedFileLength! >= 25_000 { // 25MB
                    let writingStarted = Date() // elapsed and remaining time calculation

                    // Run file size changes observer
                    observer = FileSizeObserver(url: destination, queue: completionQueue) { fileSize in
                        // Could be larger due to rough file lenght estimation
                        let fileSize = min(Int64(fileSize), estimatedFileLength - 1)
                        // guard fileSize <= writingProgress.totalUnitCount else { return }

                        // Update progress
                        writingProgress.completedUnitCount = fileSize

                        // Calculate estimated remaining time
                        if let timeRemaining = writingProgress.estimateRemainingTime(
                            startedAt: writingStarted,
                            offset: timeProgressOffset
                        ) {
                            writingProgress.estimatedTimeRemaining = timeRemaining
                        }

                        // Notify
                        callback(.progress(encoding: progress, writing: writingProgress))
                    }
                }

                // Wasn't cancelled and reached OR all operation was completed
                reader.cancelReading()
                writer.finishWriting(completionHandler: {
                    // Stop observing file size changes
                    if let observer = observer {
                        observer.finish()

                        if writingProgress.completedUnitCount != estimatedFileLength {
                            writingProgress.completedUnitCount = estimatedFileLength
                            callback(.progress(encoding: progress, writing: writingProgress))
                        }
                    }

                    // Extended file metadata
                    let data = FileExtendedAttributes.setExtendedMetadata(
                        source: source,
                        destination: destination,
                        copy: copyExtendedFileMetadata,
                        fileType: fileType
                    )

                    // Video info
                    let extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: data)
                    let videoInfo = VideoInfo(
                        url: writer.outputURL,
                        resolution: videoVariables.size.oriented(videoVariables.orientation),
                        // orientation: videoVariables.orientation,
                        frameRate: videoVariables.frameRate ?? Int(videoVariables.nominalFrameRate.rounded()),
                        totalFrames: Int(videoVariables.totalFrames),
                        duration: duration.seconds,
                        videoCodec: videoVariables.codec,
                        videoBitrate: videoVariables.bitrate,
                        hasAlpha: videoVariables.hasAlpha,
                        isHDR: videoVariables.isHDR,
                        hasAudio: !audioVariables.skipAudio,
                        audioCodec: audioVariables.codec,
                        audioBitrate: audioVariables.bitrate,
                        extendedInfo: extendedInfo
                    )

                    if deleteSourceFile, source.path != destination.path {
                        // Delete input video file
                        try? FileManager.default.removeItem(at: source)
                    }

                    // Finish
                    callback(.completed(videoInfo))
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
    internal static func initVideo(asset: AVAsset, videoSettings: CompressionVideoSettings) async throws -> VideoVariables {
        var variables = VideoVariables()

        // Get first video track, an error is raised if none found 
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }
        // variables.videoTrack = videoTrack

        // MARK: Reader
        let durationInSeconds = asset.duration.seconds
        let nominalFrameRate = videoTrack.nominalFrameRate
        let naturalTimeScale = await videoTrack.getVideoTimeScale()
        var totalFrames = Int64(ceil(durationInSeconds * Double(nominalFrameRate)))
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
            var supportedVideoCodecs: [AVVideoCodecType] = [
                .hevc,
                .hevcWithAlpha,
                .h264,
                .jpeg
            ]
            #if !os(visionOS)
            supportedVideoCodecs.append(contentsOf: [
                .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy, .proRes4444
            ])
            #endif
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
        variables.isHDR = isHDR

        // Fix the codec based on alpha support option
        // h264 do not support alpha channel, while all prores profiles do
        // hevc has two different codec variants
        if preserveAlphaChannel {
            if hasAlphaChannel {
                // Fix codec, only .hevcWithAlpha and .proRes4444 support alpha channel
                switch videoCodec! {
                case .hevc, .hevcWithAlpha:
                    videoCodec = .hevcWithAlpha
                    variables.hasAlpha = true
                #if !os(visionOS)
                case .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy, .proRes4444:
                    videoCodec = .proRes4444
                    variables.hasAlpha = true
                #endif
                case .h264, .jpeg:
                    // Codec has no alpha channel support
                    preserveAlphaChannel = false
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
        variables.codec = videoCodec!
        let videoCodecChanged = videoCodec != sourceVideoCodec

        // MARK: Writer

        // Source video resolution
        let orientation = videoTrack.orientation
        variables.orientation = orientation
        let sourceVideoSize = videoTrack.naturalSize.oriented(orientation)

        // Video settings
        var videoCompressionSettings: [String: Any] = [:]

        // Quality, ignored while bitrate is set
        if let quality = videoSettings.quality {
            videoCompressionSettings[AVVideoQualityKey] = quality
        }

        // Profile Level
        if let profile = videoSettings.profile {
            videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
        } /*else if isHDR {
            // Default profile should be adjusted for HDR content support
            if let profile = CompressionVideoProfile.profile(for: videoCodec!, bitsPerComponent: videoDesc.bitsPerComponent ?? 10) {
                videoCompressionSettings[AVVideoProfileLevelKey] = profile.rawValue
            }
        }*/

        // Frame Rate
        variables.frameRate = videoSettings.frameRate
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
            AVVideoCodecKey: videoCodec!
        ]

        // Color Information
        // https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/tagging_media_with_video_color_information
        // https://developer.apple.com/library/archive/technotes/tn2227/_index.html
        // https://developer.apple.com/documentation/avfoundation/video_settings/setting_color_properties_for_a_specific_resolution
        var colorInfo: VideoColorInformation?
        if let colorProperties = videoSettings.color {
            colorInfo = VideoColorInformation(for: colorProperties)
        } else if let colorPrimaries = videoDesc.colorPrimaries, let matrix = videoDesc.matrix, let transferFunction = videoDesc.transferFunction {
            colorInfo = VideoColorInformation(colorPrimaries: colorPrimaries, matrix: matrix, transferFunction: transferFunction)
        }
        if let colorInfo = colorInfo {
            videoParameters[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: colorInfo.colorPrimaries,
                AVVideoYCbCrMatrixKey: colorInfo.matrix,
                AVVideoTransferFunctionKey: colorInfo.transferFunction
            ]
        }

        // Video operations
        var transform = CGAffineTransform.identity
        var transformed = false // require additional transformation (rotate, flip, mirror, atd.)
        var cropRect: CGRect?
        var cutDurationInSeconds: Double?
        var frameProcessor: VideoFrameProcessor?
        for operation in videoSettings.edit {
            switch operation {
            case let .cut(from: start, to: end):
                // Apply only one cutting operation, confirm the range is valid
                if variables.range == nil,
                   let range = CMTimeRange(start: start, end: end, duration: durationInSeconds, timescale: naturalTimeScale) {
                    variables.range = range

                    // Update frames amount
                    cutDurationInSeconds = range.duration.seconds
                    totalFrames = Int64(ceil(cutDurationInSeconds! * Double(nominalFrameRate)))
                }
            case .crop(let options):
                // Get the cropping area
                let rect = options.makeCroppingRectangle(in: sourceVideoSize)
                if rect.origin == .zero && rect.size == sourceVideoSize {
                    // The cropping bounds equal to source video bounds
                    continue
                }
                guard rect.size.width >= 0, rect.size.height >= 0, rect.minX >= 0, rect.minY >= 0,
                       rect.width <= sourceVideoSize.width, rect.height <= sourceVideoSize.height else {
                    // Bounds are out of source video bounds
                    throw CompressionError.croppingOutOfBounds
                }

                // Use crop filter
                cropRect = rect
            case .rotate, .flip, .mirror:
                transform = transform.concatenating(operation.transform!)
                transformed = true
            case .process(let processor):
                // Enable video composition
                frameProcessor = processor
            }
        }

        // Video Resolution
        var videoSize = videoSettings.size.value(for: sourceVideoSize)
        var targetVideoSize = cropRect?.size ?? sourceVideoSize
        switch videoSize {
        case .fit(let size):
            // Size to fit in
            if targetVideoSize.width > size.width || targetVideoSize.height > size.height {
                // Calculate box
                let size = targetVideoSize.fit(in: size)
                // Round to nearest dividable by 2
                targetVideoSize = size.roundEven()
            } else {
                videoSize = .original
            }
        case .scale(let size):
            // Size to fill
            if targetVideoSize != size {
                targetVideoSize = size
            } else {
                videoSize = .original
            }
        default:
            break
        }
        let useVideoAdaptor = frameProcessor?.requirePixelAdaptor == true
        var useVideoComposition = frameProcessor?.canCrop != true && cropRect != nil

        #if os(visionOS)
        if useVideoComposition {
            // visionOS doesn't support video composition
            throw CompressionError.notSupportedOnVisionOS
        }
        #else
        if case .imageComposition = frameProcessor {
            useVideoComposition = true
        }
        #endif

        // Video Composition require tranformed video size, while other processors don't
        if !useVideoComposition {
            // Transform size back
            targetVideoSize = targetVideoSize.oriented(orientation)
        }

        // Set final video resolution
        videoParameters[AVVideoWidthKey] = targetVideoSize.width
        videoParameters[AVVideoHeightKey] = targetVideoSize.height

        // Context for reuse
        var context: CIContext?
        if frameProcessor?.requireCIContext == true || useVideoComposition {
            let options: [CIContextOption: Any] = [
                .highQualityDownsample: true
                // .workingFormat: CIFormat.RGBAf // kCIFormatBGRA8, kCIFormatRGBA8, kCIFormatRGBAh, kCIFormatRGBAf or nil
                // .workingColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_HLG)
            ]
            context = CIContext(options: options)
        }

        // Adjust Bitrate
        var bitrateChanged = false
        let sourceBitrate = videoTrack.estimatedDataRate.rounded()
        var targetBitrate: Int?
        if videoCodec == .h264 || videoCodec == .hevc || videoCodec == .hevcWithAlpha {
            /// Set bitrate value and update `targetBitrate` variable
            func setBitrate(_ value: Int) {
                // For the same codec use source bitrate as maximum value
                if !videoCodecChanged {
                    if value >= Int(sourceBitrate) {
                        // Use source bitrate when higher value targeted
                        videoCompressionSettings[AVVideoAverageBitRateKey] = sourceBitrate
                        return
                    } else {
                        // Require re-encoding to lower bitrate (required by the same codec only)
                        bitrateChanged = true
                    }
                }

                // Use specified bitrate value
                videoCompressionSettings[AVVideoAverageBitRateKey] = value
                targetBitrate = value
            }

            // Setting bitrate for jpeg and prores codecs is not allowed
            switch videoSettings.bitrate {
            case .value(let value):
                // videoCompressionSettings[AVVideoAverageBitRateKey] = value
                setBitrate(value)
            case .dynamic(let handler):
                setBitrate(handler(Int(sourceBitrate)))
            case .filesize(let filesize):
                // Convert MB to bits (roughly) and divide by duration
                var rate = filesize * Double(8_000_000) / (cutDurationInSeconds ?? durationInSeconds)

                // Limit based on source bit rate (H.264/AVC only)
                if videoCodecChanged && videoCodec == .h264 {
                    // When duration changed increase the limited bitrate amount by time factor
                    /*var durationFactor: Double = 1.0
                    if let cutDurationInSeconds = cutDurationInSeconds, cutDurationInSeconds != durationInSeconds {
                        durationFactor = durationInSeconds / cutDurationInSeconds
                    }*/
                    let sourceBitrate = Double(sourceBitrate) // * durationFactor
                    if rate >= sourceBitrate {
                        rate = sourceBitrate
                    }
                }

                setBitrate(Int(rate.rounded()))
            case .auto:
                var codecMultiplier: Float = 1.0
                if videoCodec == .hevc || videoCodec == .hevcWithAlpha {
                    codecMultiplier = 0.5
                } else if videoCodec == .h264 {
                    codecMultiplier = 0.9
                }
                let totalPixels = Float(targetVideoSize.width * targetVideoSize.height)
                let fps = variables.frameRate == nil ? nominalFrameRate : Float(variables.frameRate!)
                // let rate = (totalPixels * codecMultiplier * fps) / 8
                let rate = totalPixels * codecMultiplier * fps * 0.0075

                // videoCompressionSettings[AVVideoAverageBitRateKey] = rate.rounded()
                setBitrate(Int(rate.rounded()))
            case .source:
                videoCompressionSettings[AVVideoAverageBitRateKey] = sourceBitrate
                targetBitrate = Int(sourceBitrate)
            case .encoder:
                break
            }
        }
        variables.bitrate = targetBitrate
        videoParameters[AVVideoCompressionPropertiesKey] = videoCompressionSettings

        // Estimate output file size in Kilobytes
        let rate = targetBitrate == nil ? Double(sourceBitrate) : Double(targetBitrate!)
        let seconds = cutDurationInSeconds ?? durationInSeconds
        variables.estimatedFileLength = rate * (seconds / 60) * 0.0075

        // Pixel format
        let pixelFormat = !preserveAlphaChannel && frameProcessor == nil ? kCVPixelFormatType_422YpCbCr8 : kCVPixelFormatType_32BGRA
        var videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]

        // Compare source video settings with output to possibly skip video compression
        let defaultSettings = CompressionVideoSettings()
        if videoCodecChanged == false, // output codec equals source video codec
           bitrateChanged == false, // bitrate not changed
           videoSettings.quality == defaultSettings.quality, // quality set to default value
           targetVideoSize == sourceVideoSize, // output size equals source resolution
           variables.frameRate == defaultSettings.frameRate, // output frame rate greater or equals source frame rate
           !(videoSettings.preserveAlphaChannel == false && hasAlphaChannel == true), // false if alpha is removed
           videoSettings.profile?.rawValue == defaultSettings.profile?.rawValue, // profile set to default value
           videoSettings.color == defaultSettings.color, // color set to default value
           videoSettings.maxKeyFrameInterval == defaultSettings.maxKeyFrameInterval, // max ket frame set to default value
           frameProcessor == nil, // no custom sample/pixel buffer handler added
           useVideoComposition == false { // no video composition added
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
        #if os(visionOS)
        variables.videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        #else
        if useVideoComposition {
            // Make constants for concurrently-executed code
            let cropRect = cropRect
            let context = context
            let processor = frameProcessor
            let videoSize = videoSize
            let targetVideoSize = targetVideoSize

            // Scale filter for reuse
            let scaleFilter: CIFilter?
            switch videoSize {
            case .fit, .scale:
                scaleFilter = CIFilter(name: "CILanczosScaleTransform")
            default:
                scaleFilter = nil
            }

            // Composition handler
            let videoComposition = AVMutableVideoComposition(asset: asset) { request in
                //https://developer.apple.com/documentation/coreimage/processing_an_image_using_built-in_filters
                //https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci
                var image = request.sourceImage

                // Crop
                if let cropRect = cropRect {
                    image = image.cropping(to: cropRect)
                }
                // Without processor only crop applied in composition
                if processor == nil {
                    request.finish(with: image, context: context)
                    return
                }

                // Fit
                if case .fit = videoSize, let filter = scaleFilter {
                    if let scaled = image.resizing(to: targetVideoSize, using: filter) {
                        image = scaled
                    }
                }

                // Process frame & scale
                if case .imageComposition(let imageProcessor) = processor {
                    // Custom image processor
                    image = imageProcessor(image, context!, request.compositionTime.seconds)

                    // Scale (also used to fix size after processing for original/fit modes)
                    let size = image.extent.size
                    if size != targetVideoSize, let filter = scaleFilter {
                        if let scaled = image.resizing(to: targetVideoSize, using: filter) {
                            image = scaled
                        }
                    }
                }

                request.finish(with: image, context: context)
            }

            // Calculate render size
            var renderSize: CGSize?
            if processor == nil {
                // no processor (crop only)
                renderSize = cropRect?.size
            } else if case .imageComposition = processor {
                // composition processor (all - crop, fit, process and scale)
                renderSize = targetVideoSize
            } else {
                // pixel/buffer processor (crop & fit only)
                if case .fit = videoSize {
                    renderSize = targetVideoSize
                } else {
                    renderSize = cropRect?.size
                }
            }
            // Set render size
            if let renderSize = renderSize {
                videoComposition.renderSize = renderSize
            }
            // videoComposition.renderScale
            // videoComposition.frameDuration

            // Set video color information https://developer.apple.com/documentation/avfoundation/media_reading_and_writing/tagging_media_with_video_color_information#3667277
            if let colorInfo = colorInfo {
                videoComposition.colorPrimaries = colorInfo.colorPrimaries
                videoComposition.colorYCbCrMatrix = colorInfo.matrix
                videoComposition.colorTransferFunction = colorInfo.transferFunction
            }

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
        #endif

        // Video writer
        try ObjCExceptionCatcher.catchException {
            variables.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoParameters.isEmpty ? nil : videoParameters, sourceFormatHint: videoDesc)

            // Init pixel buffer adaptor
            if useVideoAdaptor {
                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                    kCVPixelBufferWidthKey as String: targetVideoSize.width,
                    kCVPixelBufferHeightKey as String: targetVideoSize.height,
                    AVVideoWidthKey: targetVideoSize.width,
                    AVVideoHeightKey: targetVideoSize.height
                ]
                variables.videoInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: variables.videoInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
            }
            return
        }

        // Transform
        if useVideoComposition {
            variables.videoInput.transform = transform
        } else {
            variables.videoInput.transform = videoTrack.fixedPreferredTransform.concatenating(transform)
        }

        /// Custom sample buffer handler (frame rate adjustment or sample processing)
        func makeVideoSampleHandler() -> ((CMSampleBuffer) -> Void)? {
            // Sample writer
            let append: (CMSampleBuffer) -> Void = { sample in
                autoreleasepool {
                    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sample)

                    var sampleBuffer: CMSampleBuffer?
                    var pixelBuffer: CVPixelBuffer?

                    switch frameProcessor {
                    case .image, .pixelBuffer: // .cgImage, .vImage
                        // Use unified processor handler
                        pixelBuffer = CVPixelBuffer.processSampleBuffer(
                            sample,
                            presentationTimeStamp: timeStamp,
                            processor: frameProcessor!,
                            videoSize: videoSize,
                            targetSize: targetVideoSize.oriented(orientation),
                            cropRect: cropRect,
                            transform: videoTrack.fixedPreferredTransform,
                            pixelBufferAdaptor: variables.videoInputAdaptor!,
                            colorInfo: colorInfo,
                            context: context
                        )
                    case .sampleBuffer(let processor):
                        // Use updated sample buffer
                        sampleBuffer = processor(sample)
                    default:
                        // Use source sample buffer
                        sampleBuffer = sample
                    }

                    // Append to write queue or drop
                    if let pixelBuffer = pixelBuffer {
                        variables.videoInputAdaptor!.append(pixelBuffer, withPresentationTime: timeStamp)
                    } else if let sampleBuffer = sampleBuffer {
                        variables.videoInput.append(sampleBuffer)
                    } else {
                        // Drop the frame
                    }
                }
            }

            guard let frameRate = variables.frameRate else {
                // Set custom processor if no frame rate adjustment required
                return frameProcessor != nil ? append : nil
            }

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
            // Update frames amount
            // totalFrames = Int64(frames.count)

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
                        append(buffer)
                    }
                }
            }
        }

        variables.sampleHandler = makeVideoSampleHandler()
        variables.nominalFrameRate = nominalFrameRate
        variables.totalFrames = totalFrames
        variables.size = targetVideoSize

        return variables
    }

    /// Initialize track, reader and writer for audio 
    internal static func initAudio(asset: AVAsset, audioSettings: CompressionAudioSettings?) async throws -> AudioVariables {
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

                // Floating-point LPCM must be 32-bit
                if isFloat == true, bitsPerChannel != 32 {
                    bitsPerChannel = 32
                }

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
                variables.codec = codec
                let audioCodecChanged = audioFormatID != codec.formatId

                var targetBitrate: Int?
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
                    if case .value(let bitrate) = audioSettings.bitrate {
                        // Setting wrong bitrate for AAC will crash the execution
                        // MPEG4AAC valid bitrate range is [64, 320]
                        if bitrate < 64000 {
                            targetBitrate = 64000
                        } else if bitrate > 320_000 {
                            targetBitrate = 320_000
                        } else {
                            targetBitrate = bitrate
                        }
                        audioParameters![AVEncoderBitRateKey] = targetBitrate!
                        variables.bitrate = targetBitrate!
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
                        // audioParameters![AVEncoderBitRateKey] = bitrate

                        if bitrate < 2000 {
                            targetBitrate = 2000
                        } else if bitrate > 510_000 {
                            targetBitrate = 510_000
                        } else {
                            targetBitrate = bitrate
                        }
                        audioParameters![AVEncoderBitRateKey] = targetBitrate!
                        variables.bitrate = targetBitrate!
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

                // Detect bitrate change
                var bitrateChanged = false
                if !audioCodecChanged, let targetBitrate = targetBitrate {
                    // Retrieve source bitrate for comparison
                    let sourceBitrate = audioTrack!.estimatedDataRateInt
                    bitrateChanged = targetBitrate < sourceBitrate
                }

                // Compare source audio settings with output to possibly skip the compression
                let defaultSettings = CompressionAudioSettings()
                if audioCodecChanged == false, // output format equals to source audio format
                   bitrateChanged == false, // bitrate not changed
                   !((audioFormatID == kAudioFormatMPEG4AAC || audioFormatID == kAudioFormatFLAC) && audioSettings.quality != defaultSettings.quality), // default settings is used for quality (aac and flac only)
                   audioSettings.sampleRate == defaultSettings.sampleRate // default settings is used for sample rate
                {
                    variables.hasChanges = false
                }
            } else {
                sourceFormatHint = audioDescription
                variables.codec = CompressionAudioCodec(formatId: audioFormatID)
            }

            if !variables.hasChanges {
                // Lossless Compression (no re-encoding required)
                audioReaderSettings = nil
                audioParameters = nil

                // Pass source format description when no changes applied
                sourceFormatHint = audioDescription
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
    internal static func initMetadata(asset: AVAsset, skipSourceMetadata: Bool, customMetadata: [AVMetadataItem]) async -> MetadataVariables {
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

    // MARK: Video Info

    /// Retvieve video file information
    /// - Parameters:
    ///   - source: Input video URL
    /// - Returns: `VideoInfo` object with collected video info
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

        // swiftlint:disable:next force_cast
        let videoDesc = videoTrack.formatDescriptions.first as! CMFormatDescription

        // Resolution
        let size = videoTrack.naturalSizeWithOrientation // videoTrack.naturalSize
        // Duration
        let duration = asset.duration.seconds
        // Frame rate
        let frameRate = videoTrack.nominalFrameRate
        // Total frames amount
        let totalFrames = Int64(ceil(duration * Double(frameRate)))
        // Video bitrate
        let videoBitrate = videoTrack.estimatedDataRate.rounded()
        // File size
        // let filesize = videoTrack.totalSampleDataLength

        // Video Codec
        let videoCodec = videoDesc.videoCodec
        // Alpha channel presence
        let hasAlpha = videoDesc.hasAlphaChannel
        // HDR
        let isHDR = videoDesc.isHDRVideo // videoTrack.hasMediaCharacteristic(.containsHDRVideo)

        // Load first audio track
        let audioTrack = await asset.getFirstTrack(withMediaType: .audio)

        // Audio info
        let hasAudio = audioTrack != nil
        var audioCodec: CompressionAudioCodec?
        var audioBitrate: Int?
        if hasAudio {
            // swiftlint:disable:next force_cast
            let audioDesc = (audioTrack!.formatDescriptions.first as! CMFormatDescription)

            // Codec
            let audioFormatID = CMFormatDescriptionGetMediaSubType(audioDesc)
            audioCodec = CompressionAudioCodec(formatId: audioFormatID)
            // Bitrate
            audioBitrate = audioTrack!.estimatedDataRateInt
        }

        // Extended info
        let rawData = FileExtendedAttributes.getExtendedMetadata(from: source.path)
        let extendedInfo = FileExtendedAttributes.extractExtendedFileInfo(from: rawData)

        return VideoInfo(
            url: source,
            resolution: size,
            // orientation: videoTrack.orientation,
            frameRate: Int(frameRate),
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
    ///     - timeToleranceBefore: Time tolerance after specified time, in seconds
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
        let nsSeconds = seconds.map({ NSValue(time: $0) })
        var counter = seconds.count
        generator.generateCGImagesAsynchronously(forTimes: nsSeconds, completionHandler: { (requestedTime, image, actualTime, _, _) in
            if let image = image {
                thumbnails.append(VideoThumbnail(image: image, requestedTime: requestedTime.seconds, actualTime: actualTime.seconds))
            }

            counter -= 1
            if counter <= 0 || thumbnails.count == seconds.count {
                completion(thumbnails)
            }
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
                // Save images in parallel with options applied
                let thumbnailQueue = DispatchQueue(label: "MediaToolSwift.video.thumbnails", qos: .userInitiated, attributes: .concurrent)
                let semaphore = DispatchSemaphore(value: 16)
                let group = DispatchGroup()
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

                    thumbnailQueue.async(group: group) {
                        do {
                            semaphore.wait()

                            // Write an image
                            let frames = [ImageFrame(cgImage: image, ciImage: ciImage)]
                            try ImageTool.saveImage(frames, at: url, settings: settings)

                            // Add to array
                            let size = ciImage?.extent.size ?? image.size
                            thumbnails.append(VideoThumbnailFile(url: url, format: settings.format, size: size, time: item.actualTime))

                            semaphore.signal()
                        } catch {
                            semaphore.signal()
                        }
                    }
                }

                group.notify(queue: thumbnailQueue) {
                    if thumbnails.isEmpty {
                        // Complete with failure when empty
                        completion(.failure(CompressionError.failedToGenerateThumbnails))
                    } else {
                        completion(.success(thumbnails))
                    }
                }
            }
        } catch let error as CompressionError {
            completion(.failure(error))
        } catch {
            completion(.failure(CompressionError.failedToGenerateThumbnails))
        }
    }
}
