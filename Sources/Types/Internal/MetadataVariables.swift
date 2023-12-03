import AVFoundation

/// Internal data type used to share local metadata related variables between code blocks
internal struct MetadataVariables {
    /// Metadata presence
    var hasMetadata = false

    /// Metadata key-values
    var metadata: [AVMetadataItem] = []

    /// Metadata reader
    var metadataOutput: AVAssetReaderOutput?

    /// Metadata writer
    var metadataInput: AVAssetWriterInput?
}
