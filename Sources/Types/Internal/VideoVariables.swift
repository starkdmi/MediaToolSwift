import AVFoundation

/// Internal data type used to share local video related variables between code blocks
internal struct VideoVariables {
    var frameRate: Int?
    var nominalFrameRate: Float!
    var totalFrames: Int64!
    var range: CMTimeRange?
    var sampleHandler: ((CMSampleBuffer) -> Void)?
    var hasChanges = true
    var videoOutput: AVAssetReaderOutput!
    var videoInput: AVAssetWriterInput!
}
