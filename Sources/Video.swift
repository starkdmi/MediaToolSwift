import AVFoundation
import Foundation
import CoreMedia
import VideoToolbox

// To support both SwiftPM and CocoaPods
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

public class VideoTool {

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
    public class func convert(
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

            if videoVariables.shouldCompress == false {
                // Additionally load audio track to check if source file has audio 
                audioVariables.audioTrack = await asset.getFirstTrack(withMediaType: .audio)
                audioVariables.shouldCompress = audioVariables.audioTrack != nil
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
        if !videoVariables.shouldCompress, !audioVariables.shouldCompress {
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
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

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
    private class func initVideo(asset: AVAsset, videoSettings: CompressionVideoSettings) async throws -> VideoVariables {
        var variables = VideoVariables()

        // Get first video track, an error is raised if none found 
        guard let videoTrack = await asset.getFirstTrack(withMediaType: .video) else {
            throw CompressionError.videoTrackNotFound
        }

        // MARK: Reader
        // Total Frames used for progress calculation
        let durationInSeconds = asset.duration.seconds
        let nominalFrameRate = videoTrack.nominalFrameRate
        let totalFrames = Int64(ceil(durationInSeconds * Double(nominalFrameRate)))
        // ffmpeg command to get frames amount:
        // ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -print_format csv video.mp4

        // Video codec
        // swiftlint:disable:next force_cast
        let videoDesc = videoTrack.formatDescriptions.first as! CMFormatDescription
        let sourceVideoCodec = videoDesc.videoCodec
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

        // HDR videos can't have an alpha channel
        var preserveAlphaChannel = videoSettings.preserveAlphaChannel
        if preserveAlphaChannel, videoDesc.isHDRVideo {
            preserveAlphaChannel = false
        }

        // Fix the codec based on alpha support option
        // h264 do not support alpha channel, while all prores profiles do
        // hevc has two different codec variants
        let hasAlphaChannel = videoDesc.hasAlphaChannel
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

        let videoReaderSettings: [String: Any] = [
            // Pixel format
            kCVPixelBufferPixelFormatTypeKey as String:
                preserveAlphaChannel ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_422YpCbCr8
        ]

        variables.videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        // Video composition
        // variables.videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: videoReaderSettings)
        // variables.videoOutput.videoComposition = composition

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
        if let frameRate = variables.frameRate, frameRate < Int(round(nominalFrameRate)) {
            // Note: The [AVVideoExpectedSourceFrameRateKey] is just a hint to the encoder about the expected source frame rate, and the encoder is free to ignore it
            if videoCodec == .hevc || videoCodec == .hevcWithAlpha {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
            } else if videoCodec == .h264 {
                videoCompressionSettings[AVVideoExpectedSourceFrameRateKey] = frameRate
                #if os(OSX)
                videoCompressionSettings[AVVideoAverageNonDroppableFrameRateKey] = frameRate
                #endif
            }
        } else {
            // Frame rate is nil, more or equal to source video frame rate
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

        try ObjCExceptionCatcher.catchException {
            variables.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoParameters, sourceFormatHint: videoDesc)
        }
        variables.videoInput.transform = videoTrack.fixedPreferredTransform // videoTrack.preferredTransform

        /// Custom sample buffer handler for video to adjust frame rate
        func makeVideoSampleHandler() -> ((CMSampleBuffer) -> Void)? {
            guard let frameRate = variables.frameRate, Float(frameRate) < nominalFrameRate else { return nil }
            // Frame rate - skip frames and update time stamp & duration of each saved frame
            // Info: Another approach to adjust video frame rate is using AVAssetReaderVideoCompositionOutput
            // Info: It also possible using CMSampleBufferSetOutputPresentationTimeStamp().convertScale(timeScale, method: .quickTime)

            // The frame rate in current implementation is always an integer, so the Time Scale set to frame rate
            // https://developer.apple.com/library/archive/qa/qa1447/_index.html
            let timeScale = CMTimeScale(frameRate)
            variables.videoInput.mediaTimeScale = timeScale

            // Find frames which will be written (not skipped)
            let targetFrames = Int(round(Float(totalFrames) * Float(frameRate) / nominalFrameRate))
            var frames: Set<Int> = []
            frames.reserveCapacity(targetFrames)
            // Add first frame index (starting from one)
            frames.insert(1)
            // Find other desired frame indexes
            for i in 1 ..< targetFrames {
                frames.insert(Int(ceil(Double(totalFrames) * Double(i) / Double(targetFrames - 1))))
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
                    timingInfo.duration = CMTimeMake(value: 1, timescale: timeScale)

                    // Update the sample timing info
                    if let previousPresentationTimeStamp = previousPresentationTimeStamp {
                        // Calculate the new presentation time stamp
                        timingInfo.presentationTimeStamp = CMTimeAdd(previousPresentationTimeStamp, timingInfo.duration)
                    } else {
                        // First frame
                        timingInfo.presentationTimeStamp = CMTime(value: .zero, timescale: timeScale)
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

        // Compare source video settings with output to possibly skip the compression
        let defaultSettings = CompressionVideoSettings()
        if videoCodec == sourceVideoCodec, // output codec equals source video codec
           videoSettings.bitrate == defaultSettings.bitrate, // bitrate set to default value
           videoSettings.quality == defaultSettings.quality, // quality set to default value
           videoSize == sourceVideoSize, // output size equals source resolution
           variables.frameRate == defaultSettings.frameRate, // output frame rate equals source frame rate
           !(videoSettings.preserveAlphaChannel == false && hasAlphaChannel == true), // false if alpha is removed
           videoSettings.profile?.rawValue == defaultSettings.profile?.rawValue, // profile set to default value
           videoSettings.color == defaultSettings.color, // color set to default value
           videoSettings.maxKeyFrameInterval == defaultSettings.maxKeyFrameInterval { // max ket frame set to default value
            variables.shouldCompress = false
        }

        return variables
    }

    /// Initialize track, reader and writer for audio 
    private class func initAudio(asset: AVAsset, audioSettings: CompressionAudioSettings?) async throws -> AudioVariables {
        var variables = AudioVariables()

        // Load first audio track if any
        let audioTrack = await asset.getFirstTrack(withMediaType: .audio)
        variables.audioTrack = audioTrack
        if audioTrack == nil {
            variables.skipAudio = true
            variables.shouldCompress = false
            return variables
        }
        if audioSettings == nil {
            variables.shouldCompress = false
        }

        // MARK: Reader
        var bitsPerChannel, channelsPerFrame: Int?
        var isFloat, isBigEndian: Bool?
        if !variables.skipAudio {
            var audioReaderSettings: [String: Any]?
            if let audioSettings = audioSettings {
                // Retvieve source info
                var sampleRate: Int?
                // swiftlint:disable:next force_cast
                let audioDescription = audioTrack!.formatDescriptions.first as! CMFormatDescription
                let basicDescription = audioDescription.audioStreamBasicDescription

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
            variables.audioOutput = AVAssetReaderTrackOutput(track: audioTrack!, outputSettings: audioReaderSettings)
        }

        // MARK: Writer
        if !variables.skipAudio {
            // swiftlint:disable:next force_cast
            let audioDesc = audioTrack!.formatDescriptions.first as! CMFormatDescription
            let audioFormatID = CMFormatDescriptionGetMediaSubType(audioDesc)

            var sourceFormatHint: CMFormatDescription?
            var audioParameters: [String: Any]?
            if let audioSettings = audioSettings {
                // Audio settings 
                // https://developer.apple.com/documentation/avfoundation/audio_settings

                var codec = audioSettings.codec
                if codec == .default, let sourceCodec = CompressionAudioCodec(formatId: audioFormatID), sourceCodec != .default {
                    // Use source audio format
                    codec = sourceCodec
                    variables.shouldCompress = false
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
                    sourceFormatHint = audioDesc
                    variables.shouldCompress = false
                }

                // Compare source audio settings with output to possibly skip the compression
                let defaultSettings = CompressionAudioSettings()
                if audioFormatID == codec.formatId, // output format equals to source audio format
                   audioSettings.bitrate == defaultSettings.bitrate, // default settings is used for bitrate
                   !((audioFormatID == kAudioFormatMPEG4AAC || audioFormatID == kAudioFormatFLAC) && audioSettings.quality != defaultSettings.quality), // default settings is used for quality (aac and flac only)
                   audioSettings.sampleRate == defaultSettings.sampleRate // default settings is used for sample rate
                {
                    variables.shouldCompress = false
                }
            } else {
                sourceFormatHint = audioDesc
            }

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
    private class func initMetadata(asset: AVAsset, skipSourceMetadata: Bool, customMetadata: [AVMetadataItem]) async -> MetadataVariables {
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

}
