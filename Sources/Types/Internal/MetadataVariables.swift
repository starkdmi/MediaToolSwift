import AVFoundation

/// Internal data type used to share local metadata related variables between code blocks
internal struct MetadataVariables {
    var hasMetadata = false
    var metadata: [AVMetadataItem] = []
    var metadataOutput: AVAssetReaderOutput?
    var metadataInput: AVAssetWriterInput?
}
