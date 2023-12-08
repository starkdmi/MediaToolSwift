import Foundation

/// Audio information
public struct AudioInfo: MediaInfo {
    /// Public initializer
    public init(
        url: URL,
        duration: Double,
        codec: CompressionAudioCodec?,
        bitrate: Int?,
        extendedInfo: ExtendedFileInfo?
    ) {
        self.url = url
        self.duration = duration
        self.codec = codec
        self.bitrate = bitrate
        self.extendedInfo = extendedInfo
    }

    /// Audio file path
    public let url: URL

    /// Audio duration, in seconds
    public let duration: Double

    /// Audio codec
    public let codec: CompressionAudioCodec?

    /// Audio bitrate, in bits
    public let bitrate: Int?

    /// Extended media information
    public let extendedInfo: ExtendedFileInfo?
}
