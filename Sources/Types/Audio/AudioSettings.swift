import AVFoundation

/// All-in-one audio settings
public struct CompressionAudioSettings {
    /// Public initializer with default settings
    public init(
        codec: CompressionAudioCodec = .default,
        bitrate: Int? = nil,
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
    let codec: CompressionAudioCodec

    /// Bitrate in bits, used only by AAC and Opus
    /// Warning: Providing bitrate which is invalid for selected codec will crash the application execution
    let bitrate: Int?

    /// Audio quality, used by AAC and FLAC
    let quality: AVAudioQuality?

    /// Sample rate
    let sampleRate: Int?

    /// Audio volume, 0.0 is muted
    // let volume: Float // [0.0, 1.0]
}
