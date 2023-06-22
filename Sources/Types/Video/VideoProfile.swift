import AVFoundation
import VideoToolbox

/// Profiles used by video encoder
public enum CompressionVideoProfile {
    // MARK: H.264 Profiles

    /// Baseline Auto Level
    case h264Baseline

    /// Main Auto Level
    case h264Main

    /// High Auto Level
    case h264High

    /// Extended Auto Level
    case h264Extended

    // MARK: H.265/HEVC Profiles

    /// Main Auto Level
    case hevcMain

    /// Main10 Auto Level
    case hevcMain10

    /// Main42210 Auto Level (iOS 15.4+, macOS 12.3+)
    case hevcMain42210

    /// User specified profile
    /// Values like `AVVideoProfileLevelH264HighAutoLevel` as well as VideoToolBox's `kVTProfileLevel_HEVC_High_AutoLevel` allowed
    case value(String)
}

/// Video profiles bandwidth level
public enum CompressionVideoProfileBandwidth {
    case low, medium, high
}

public extension CompressionVideoProfile {
    /// Provide appropriative profile string
    var rawValue: String {
        switch self {
        // H.264
        case .h264Baseline:
            return AVVideoProfileLevelH264BaselineAutoLevel
        case .h264Main:
            return AVVideoProfileLevelH264MainAutoLevel
        case .h264High:
            return AVVideoProfileLevelH264HighAutoLevel
        case .h264Extended:
            return kVTProfileLevel_H264_Extended_AutoLevel as String
        // HEVC
        case .hevcMain:
            return kVTProfileLevel_HEVC_Main_AutoLevel as String
        case .hevcMain10:
            return kVTProfileLevel_HEVC_Main10_AutoLevel as String
        case .hevcMain42210:
            var profile: String
            if #available(iOS 15.4, OSX 12.3, tvOS 15.4, *) {
                profile = kVTProfileLevel_HEVC_Main42210_AutoLevel as String
            } else {
                profile = kVTProfileLevel_HEVC_Main10_AutoLevel as String
            }
            return profile
        // Custom
        case .value(let value):
            return value
        }
    }

    /// Calculate video profile based on codec, bits and quality
    /// Warning: Used by Video Composition only
    static func profile(for codec: AVVideoCodecType, bitsPerComponent: Int, bandwidth: CompressionVideoProfileBandwidth = .medium) -> CompressionVideoProfile? {
        switch codec {
        case .h264:
            switch bandwidth {
            case .low:
                if bitsPerComponent >= 10 { fallthrough }
                return .h264Baseline
            case .medium:
                if bitsPerComponent > 10 { fallthrough }
                return .h264Main
            case .high:
                return .h264High
            }
        case .hevc:
            switch bandwidth {
            case .low:
                if bitsPerComponent > 8 { fallthrough }
                return .hevcMain
            case .medium:
                return .hevcMain10
            case .high:
                return .hevcMain42210
            }
        case .hevcWithAlpha:
            return .hevcMain
        default:
            break
        }

        return nil
    }
}
