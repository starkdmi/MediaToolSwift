import AVFoundation

/// Internal data type used to share local audio related variables between code blocks
internal struct AudioVariables {
    var skipAudio = false
    var audioTrack: AVAssetTrack?
    var shouldCompress = true
    var audioOutput: AVAssetReaderOutput?
    var audioInput: AVAssetWriterInput?
}
