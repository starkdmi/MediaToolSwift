import AVFoundation
import CoreMedia
import VideoToolbox

/// Analyzes a video track to extract its properties.
internal struct VideoTrackAnalyzer {

    /// Result of video track analysis
    internal struct Analysis {
        /// The video track's format description
        internal let formatDescription: CMFormatDescription

        /// Source video codec
        internal let codec: AVVideoCodecType

        /// Natural size of the video (may differ from encoded size for non-square pixels)
        internal let naturalSize: CGSize

        /// Preferred transform with invalid translation components corrected
        internal let fixedPreferredTransform: CGAffineTransform

        /// Encoded pixel dimensions (actual pixel count)
        internal let encodedSize: CGSize

        /// Video orientation from track transform
        internal let orientation: VideoOrientation

        /// Nominal frame rate (frames per second)
        internal let nominalFrameRate: Float

        /// Video time scale
        internal let timeScale: CMTimeScale

        /// Total duration
        internal let duration: CMTime

        /// Total frames count (estimated)
        internal let totalFrames: Int64

        /// Whether the video has an alpha channel
        internal let hasAlpha: Bool

        /// Whether the video is HDR
        internal let isHDR: Bool

        /// Color primaries (if available)
        internal let colorPrimaries: String?

        /// Color matrix (if available)
        internal let colorMatrix: String?

        /// Color transfer function (if available)
        internal let colorTransferFunction: String?

        /// Bits per component
        internal let bitsPerComponent: Int?

        /// Source video size accounting for orientation
        internal var sourceVideoSize: CGSize {
            if encodedSize != naturalSize {
                // Video has non-square PAR
                return encodedSize.oriented(orientation)
            } else {
                return naturalSize.oriented(orientation)
            }
        }

        /// Source bitrate reported by AVFoundation
        internal let estimatedDataRate: Float
    }

    internal init() {}

    /// Analyze a video track
    /// - Parameters:
    ///   - track: The video track to analyze
    ///   - asset: The asset containing the track (for duration)
    /// - Returns: Analysis result with all track properties
    /// - Throws: CompressionError if track analysis fails
    internal func analyze(track: AVAssetTrack, asset: AVAsset) async throws -> Analysis {
        guard let formatDescription = await track.getFormatDescriptions().first else {
            throw CompressionError.failedToReadVideo
        }

        // Duration and frame rate
        let duration = await asset.getDuration()
        let nominalFrameRate = await track.getNominalFrameRate()
        let timeScale = await track.getVideoTimeScale()
        let totalFrames = Int64(ceil(duration.seconds * Double(nominalFrameRate)))

        // Codec
        let hasAlphaChannel = formatDescription.hasAlphaChannel
        var codec = formatDescription.videoCodec
        if codec == .hevc, hasAlphaChannel {
            // Fix muxa video codec
            codec = .hevcWithAlpha
        }

        // HDR detection
        let isHDR = formatDescription.isHDRVideo

        // Sizes
        let naturalSize = await track.getNaturalSize()
        let fixedPreferredTransform = await track.getFixedPreferredTransform()
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let encodedSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))

        // Orientation
        let orientation = await track.getOrientation()
        let estimatedDataRate = await track.getEstimatedDataRate()

        // Color information
        let colorPrimaries = formatDescription.colorPrimaries
        let colorMatrix = formatDescription.matrix
        let colorTransferFunction = formatDescription.transferFunction
        let bitsPerComponent = formatDescription.bitsPerComponent

        return Analysis(
            formatDescription: formatDescription,
            codec: codec,
            naturalSize: naturalSize,
            fixedPreferredTransform: fixedPreferredTransform,
            encodedSize: encodedSize,
            orientation: orientation,
            nominalFrameRate: nominalFrameRate,
            timeScale: timeScale,
            duration: duration,
            totalFrames: totalFrames,
            hasAlpha: hasAlphaChannel,
            isHDR: isHDR,
            colorPrimaries: colorPrimaries,
            colorMatrix: colorMatrix,
            colorTransferFunction: colorTransferFunction,
            bitsPerComponent: bitsPerComponent,
            estimatedDataRate: estimatedDataRate
        )
    }

    /// Register supplemental video decoders if needed (macOS only)
    /// - Parameter formatDescription: The format description to check
    internal func registerSupplementalDecodersIfNeeded(for formatDescription: CMFormatDescription) {
        #if os(macOS)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        switch mediaSubType {
        case kCMVideoCodecType_VP9:
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        case kCMVideoCodecType_AV1:
            VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)
        default:
            break
        }
        #endif
    }
}
