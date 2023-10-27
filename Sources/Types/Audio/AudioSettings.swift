import AVFoundation

/// All-in-one audio settings
public struct CompressionAudioSettings {
    /// Public initializer with default settings
    public init(
        codec: CompressionAudioCodec = .default,
        bitrate: CompressionAudioBitrate = .auto,
        quality: AVAudioQuality? = nil,
        sampleRate: Int? = nil
        // volume: Float = 1.0
    ) {
        self.codec = codec
        self.bitrate = bitrate
        self.quality = quality
        self.sampleRate = sampleRate
        // self.volume = volume
    }

    /// Audio codec used for compression
    public let codec: CompressionAudioCodec

    /// Audio bitrate, used only by AAC and Opus
    /// Enum case `.value(Int)` requires value in bits
    /// Values in range from 64000 to 320000 are valid for AAC audio codec
    /// Values in range from 2000 to 510000 are valid for Opus audio codec
    public let bitrate: CompressionAudioBitrate

    /// Audio quality, used by AAC and FLAC
    public let quality: AVAudioQuality?

    /// Sample rate
    public let sampleRate: Int?

    /// Audio volume, 0.0 is muted
    // public let volume: Float // [0.0, 1.0]
}
