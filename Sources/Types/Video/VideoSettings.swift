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
        hardwareAcceleration: CompressionHardwareAcceleration = .auto,
        edit: Set<VideoOperation> = []
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
        self.edit = edit
    }

    /// Video codec used for compression, use `nil` for source video codec
    public let codec: AVVideoCodecType? // h264, hevc, hevcWithAlpha, ...

    /// Bitrate, `.value(Int)` requires value in bits, ignored by ProRes and JPEG
    public let bitrate: CompressionVideoBitrate // .auto, .encoder, .value(2_000_000)

    /// Quality used only when `bitrate` set to `.encoder`, range: [0.0, 1.0]
    /// Not all the codecs support `quality` to be set
    public let quality: Double?

    /// Size to fit video in while preserving aspect ratio, width and height may be rounded to be divisible by 2
    /// On macOS value of 405 may be scalled down to 404, while on iOS stay 405
    /// For best results, always use even number values for width and height when encoding to H.264 or any other format that uses 4:2:0 downsampling
    public let size: CGSize? // CGSize(width: 1280.0, height: 1280.0)

    /// Frame rate, will not increase source video frame rate
    public let frameRate: Int?

    /// Indicates to save alpha channel or drop
    /// Do nothing for video files without alpha channel
    public let preserveAlphaChannel: Bool

    /// Profile used by video encoder
    /// Prores profiles are specified by `codec` not the `profile` property
    public let profile: CompressionVideoProfile?

    /// Color Primary
    public let color: CompressionColorPrimary?

    /// Maximum interval between keyframes
    public let maxKeyFrameInterval: Int?

    /// Hardware Acceleration
    public let hardwareAcceleration: CompressionHardwareAcceleration

    /// Video specific operations like cut, rotate, crop
    /// Only one operation of each type is applied
    public let edit: Set<VideoOperation>
}
