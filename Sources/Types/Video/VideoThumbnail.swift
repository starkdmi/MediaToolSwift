import AVFoundation

/// Video thumbnail as `CGImage`
public struct VideoThumbnail {
    /// Thumbnail image
    public let image: CGImage

    /// Requested thumbnail time
    public let requestedTime: Double

    /// Actual thumbnail frame time
    public let actualTime: Double
}
