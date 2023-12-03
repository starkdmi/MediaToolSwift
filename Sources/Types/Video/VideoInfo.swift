import AVFoundation
import CoreLocation

/// Video information
struct VideoInfo {
    /// Video resolution
    let resolution: CGSize

    /// Frame rate
    let frameRate: Int

    /// Frames amount
    let totalFrames: Int

    /// Video duration, in seconds
    let duration: Double

    /// Video codec
    let videoCodec: AVVideoCodecType

    /// Video bitrate
    let videoBitrate: Int?

    /// Alpha channel presence
    let hasAlpha: Bool

    /// HDR data presence
    let isHDR: Bool

    /// Audio track presence
    let hasAudio: Bool

    /// Audio codec
    let audioCodec: CompressionAudioCodec

    /// Audio bitrate
    let audioBitrate: Int?

    /// Extended video information
    let extendedInfo: ExtendedVideoInfo?
}

/// Additional video information
struct ExtendedVideoInfo {
    /// Original date
    let date: Date

    /// Location
    let location: CLLocation?

    /// Where from
    let whereFrom: [String]

    /// Original file name
    let originalFilename: String

    /// File size
    let filesize: Int64?
}
