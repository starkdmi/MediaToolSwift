import AVFoundation
import CoreLocation

/// Video information
public struct VideoInfo {
    /// Public initializer
    public init(
        resolution: CGSize,
        frameRate: Int,
        totalFrames: Int,
        duration: Double,
        videoCodec: AVVideoCodecType,
        videoBitrate: Int?,
        hasAlpha: Bool,
        isHDR: Bool,
        hasAudio: Bool,
        audioCodec: CompressionAudioCodec,
        audioBitrate: Int?,
        extendedInfo: ExtendedVideoInfo?
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.totalFrames = totalFrames
        self.duration = duration
        self.videoCodec = videoCodec
        self.videoBitrate = videoBitrate
        self.hasAlpha = hasAlpha
        self.isHDR = isHDR
        self.hasAudio = hasAudio
        self.audioCodec = audioCodec
        self.audioBitrate = audioBitrate
        self.extendedInfo = extendedInfo
    }

    /// Video resolution
    public let resolution: CGSize

    /// Frame rate
    public let frameRate: Int

    /// Frames amount
    public let totalFrames: Int

    /// Video duration, in seconds
    public let duration: Double

    /// Video codec
    public let videoCodec: AVVideoCodecType

    /// Video bitrate
    public let videoBitrate: Int?

    /// Alpha channel presence
    public let hasAlpha: Bool

    /// HDR data presence
    public let isHDR: Bool

    /// Audio track presence
    public let hasAudio: Bool

    /// Audio codec
    public let audioCodec: CompressionAudioCodec

    /// Audio bitrate
    public let audioBitrate: Int?

    /// Extended video information
    public let extendedInfo: ExtendedVideoInfo?
}

/// Additional video information
public struct ExtendedVideoInfo {
    /// Public initializer
    public init(
        date: Date,
        location: CLLocation?,
        whereFrom: [String],
        originalFilename: String,
        filesize: Int64?
    ) {
        self.date = date
        self.location = location
        self.whereFrom = whereFrom
        self.originalFilename = originalFilename
        self.filesize = filesize
    }

    /// Original date
    public let date: Date

    /// Location
    public let location: CLLocation?

    /// Where from
    public let whereFrom: [String]

    /// Original file name
    public let originalFilename: String

    /// File size
    public let filesize: Int64?
}
