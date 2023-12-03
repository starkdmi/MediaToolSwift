import AVFoundation

/// Internal data type used to share local audio related variables between code blocks
internal struct AudioVariables {
    /// Flag to skip audio
    var skipAudio = false

    /// Audio track
    var audioTrack: AVAssetTrack?

    // Require to encode
    var hasChanges = true

    // Audio reader
    var audioOutput: AVAssetReaderOutput?

    // Audio writer
    var audioInput: AVAssetWriterInput?
}
