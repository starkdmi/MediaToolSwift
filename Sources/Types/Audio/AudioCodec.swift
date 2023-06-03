import AVFoundation

/// Available audio codecs
public enum CompressionAudioCodec: Int {
    /// Audio codec set internally by `AVAssetWriter`
    case `default` = 0

    /// AAC
    case aac

    /// Opus
    case opus

    /// Flac
    case flac

    /// Linear PCM
    case lpcm

    /// AudioFormatID associated with enum case
    public var formatId: AudioFormatID? {
        switch self {
        case .default:
            return nil
        case .aac:
            return kAudioFormatMPEG4AAC
        case .opus:
            return kAudioFormatOpus
        case .flac:
            return kAudioFormatFLAC
        case .lpcm:
            return kAudioFormatLinearPCM
        }
    }
}
