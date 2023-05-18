/// Video bitrate settings
public enum CompressionVideoBitrate: Equatable {
    /// Bitrate calculated based on resolution, frame rate and codec
    case auto

    /// Bitrate automatically set by [AVAssetWriter] internally
    case encoder

    /// User specified bitrate in bits
    case custom(Int)

    /// Equatable conformation
    public static func == (lhs: CompressionVideoBitrate, rhs: CompressionVideoBitrate) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.encoder, .encoder):
            return true
        case (.custom(let lhsValue), .custom(let rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}
