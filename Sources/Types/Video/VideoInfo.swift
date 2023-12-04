import AVFoundation

/// Video information
public struct VideoInfo: MediaInfo {
    /// Public initializer
    public init(
        url: URL,
        resolution: CGSize,
        frameRate: Int,
        totalFrames: Int,
        duration: Double,
        videoCodec: AVVideoCodecType,
        videoBitrate: Int?,
        hasAlpha: Bool,
        isHDR: Bool,
        hasAudio: Bool,
        audioCodec: CompressionAudioCodec?,
        audioBitrate: Int?,
        extendedInfo: ExtendedFileInfo?
    ) {
        self.url = url
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

    /// Video file path
    public let url: URL

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

    /// Video bitrate, in bits
    public let videoBitrate: Int?

    /// Alpha channel presence
    public let hasAlpha: Bool

    /// HDR data presence
    public let isHDR: Bool

    /// Audio track presence
    public let hasAudio: Bool

    /// Audio codec
    public let audioCodec: CompressionAudioCodec?

    /// Audio bitrate, in bits
    public let audioBitrate: Int?

    /// Extended media information
    public let extendedInfo: ExtendedFileInfo?
}
