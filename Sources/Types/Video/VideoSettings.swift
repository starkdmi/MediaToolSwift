import AVFoundation

/// All-in-one video settings
public struct CompressionVideoSettings {
    /// Public initializer with default settings
    public init(
        codec: AVVideoCodecType? = nil,
        bitrate: CompressionVideoBitrate = .auto,
        quality: Double? = nil,
        size: CGSize? = nil,
        frameRate: Int? = nil,
        preserveAlphaChannel: Bool = true,
        profile: CompressionVideoProfile? = nil,
        color: CompressionColorPrimary? = nil,
        maxKeyFrameInterval: Int? = nil,
        hardwareAcceleration: CompressionHardwareAcceleration = .auto
    ) {
        self.codec = codec
        self.bitrate = bitrate
        self.quality = quality
        self.size = size
        self.frameRate = frameRate
        self.preserveAlphaChannel = preserveAlphaChannel
        self.profile = profile
        self.color = color
        self.maxKeyFrameInterval = maxKeyFrameInterval
        self.hardwareAcceleration = hardwareAcceleration
    }

    /// Video codec used for compression, use [nil] for source video codec
    let codec: AVVideoCodecType? // h264, hevc, hevcWithAlpha, ...

    /// Bitrate, CompressionVideoBitrate.custom(Int) requires value in bits, ignored by Prores and JPEG
    let bitrate: CompressionVideoBitrate // .auto, .encoder, .custom(2000000)

    /// Quality used only when [bitrate] set to `.encoder`, range: [0.0, 1.0]
    /// Not all the codecs support [quality] to be set
    let quality: Double?

    /// Size to fit video in while preserving aspect ratio, width and height may be rounded to be divisible by 2
    let size: CGSize? // CGSize(width: 1280.0, height: 1280.0)

    /// Frame rate will not increase resulting video frame rate, set [bitrate] to .auto for lower file size when [frameRate] is set
    /// Warning: Use with caution, frame rate adjustment isn't well documented and uses code for skipping frames manually
    let frameRate: Int?

    /// Indicates to save alpha channel or drop
    /// Do nothing for video files without alpha channel
    let preserveAlphaChannel: Bool

    /// Profile used by video encoder
    /// Prores profiles are specified by [codec] not the [profile] property
    let profile: CompressionVideoProfile?

    /// Color Primary
    let color: CompressionColorPrimary?

    /// Maximum interval between keyframes
    let maxKeyFrameInterval: Int?

    /// Hardware Acceleration
    let hardwareAcceleration: CompressionHardwareAcceleration
}
