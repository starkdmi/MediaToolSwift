import AVFoundation

/// Audio file container
public enum AudioFileType: String {
    /// MPEG-4
    case m4a

    /// Core Audio
    case caf

    /// WAVE (Lossless)
    case wav

    /// AIFF (Lossless)
    case aiff

    /// AIFC
    case aifc

    /// Adaptive Multirate
    case amr

    /// AVFileType associated with enum case
    public var value: AVFileType {
        switch self {
        case .m4a:
            return AVFileType.m4a
        case .caf:
            return AVFileType.caf
        case .wav:
            return AVFileType.wav
        case .aiff:
            return AVFileType.aiff
        case .aifc:
            return AVFileType.aifc
        case .amr:
            return AVFileType.amr
        }
    }
}
