/// Audio bitrate settings
public enum CompressionAudioBitrate: Equatable {
    /// Bitrate automatically set by `AVAssetWriter` internally
    case auto

    /// User specified bitrate in bits
    case value(Int)

    /// Equatable conformation
    public static func == (lhs: CompressionAudioBitrate, rhs: CompressionAudioBitrate) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.value(let lhsValue), .value(let rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}
