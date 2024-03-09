import AVFoundation

/// Internal data type used to share local video related variables between code blocks
internal struct VideoVariables {
    /// Target fps
    var frameRate: Int?

    /// Source fps
    var nominalFrameRate: Float!

    // Frames amount
    var totalFrames: Int64!

    /// Cut range
    var range: CMTimeRange?

    /// Frame modifier
    var sampleHandler: ((CMSampleBuffer) -> Void)?

    /// Require to encode
    var hasChanges = true

    /// Video track
    // var videoTrack: AVAssetTrack?

    /// Video reader
    var videoOutput: AVAssetReaderOutput!

    /// Video writer
    var videoInput: AVAssetWriterInput!

    /// Video writer adaptor
    var videoInputAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // MARK: Video info variables

    /// Video resolution
    var size: CGSize!

    /// Video orientation
    var orientation: VideoOrientation!

    /// Video codec
    var codec: AVVideoCodecType!

    /// Video bitrate
    var bitrate: Int?

    /// Estimated output file size in Kilobytes
    var estimatedFileLength: Double!

    /// Alpha channel presence
    var hasAlpha: Bool = false

    /// HDR data presence
    var isHDR: Bool = false
}
