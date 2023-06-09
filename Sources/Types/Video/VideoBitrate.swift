/// Video bitrate settings
public enum CompressionVideoBitrate: Equatable {
    /// Bitrate calculated based on resolution, frame rate and codec
    case auto

    /// Bitrate automatically set by `AVAssetWriter` internally
    case encoder

    /// Source video bitrate
    case source

    /// User specified bitrate in bits
    case value(Int)

    /// Equatable conformation
    public static func == (lhs: CompressionVideoBitrate, rhs: CompressionVideoBitrate) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.encoder, .encoder):
            return true
        case (.source, .source):
            return true
        case (.value(let lhsValue), .value(let rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}
