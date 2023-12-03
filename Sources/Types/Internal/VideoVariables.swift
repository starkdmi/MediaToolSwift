import AVFoundation

/// Internal data type used to share local video related variables between code blocks
internal struct VideoVariables {
    /// Target fps
    var frameRate: Int?

    /// Source fps
    var nominalFrameRate: Float!

    /// Cut range
    var range: CMTimeRange?

    /// Frame modifier
    var sampleHandler: ((CMSampleBuffer) -> Void)?

    /// Require to encode
    var hasChanges = true

    /// Video reader
    var videoOutput: AVAssetReaderOutput!

    /// Video writer
    var videoInput: AVAssetWriterInput!
}
