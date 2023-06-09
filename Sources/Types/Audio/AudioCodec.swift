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

    /// Apple Lossless Audio Codec
    case alac

    /// Initialize using `AudioFormatID` value
    init?(formatId: AudioFormatID) {
        switch formatId {
        case kAudioFormatMPEG4AAC:
            self.init(rawValue: 1)
        case kAudioFormatOpus:
            self.init(rawValue: 2)
        case kAudioFormatFLAC:
            self.init(rawValue: 3)
        case kAudioFormatLinearPCM:
            self.init(rawValue: 4)
        case kAudioFormatAppleLossless:
            self.init(rawValue: 5)
        default:
            self.init(formatId: 0)
        }
    }

    /// `AudioFormatID` associated with enum case
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
        case .alac:
            return kAudioFormatAppleLossless
        }
    }
}
