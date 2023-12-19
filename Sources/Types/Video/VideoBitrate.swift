/// Video bitrate settings
public enum CompressionVideoBitrate: Equatable {
    /// Bitrate calculated based on resolution, frame rate and codec
    case auto

    /// Bitrate automatically set by `AVAssetWriter` internally
    case encoder

    /// Source video bitrate
    case source

    /// Calculate bitrate to target file size, in megabytes
    /// Accurate for target size higher than `0.5` MB
    case filesize(_ MBs: Double)

    /// User specified bitrate in bits
    case value(_ bits: Int)

    /// Equatable conformation
    public static func == (lhs: CompressionVideoBitrate, rhs: CompressionVideoBitrate) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.encoder, .encoder):
            return true
        case (.source, .source):
            return true
        case (.filesize(let lhsValue), .filesize(let rhsValue)):
            return lhsValue == rhsValue
        case (.value(let lhsValue), .value(let rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}
