import AVFoundation

/// Video file container
public enum CompressionFileType {
    /// MPEG-4
    case mp4

    /// QuickTime
    case mov

    /// iTunes
    case m4v

    /// AVFileType associated with enum case
    public var rawValue: AVFileType {
        switch self {
        case .mp4:
            return AVFileType.mp4
        case .mov:
            return AVFileType.mov
        case .m4v:
            return AVFileType.m4v
        }
    }
}
