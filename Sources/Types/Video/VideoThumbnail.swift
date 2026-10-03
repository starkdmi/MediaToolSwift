import AVFoundation

/// Video thumbnail as `CGImage`
public struct VideoThumbnail: Sendable {
    /// Thumbnail image
    public let image: CGImage

    /// Requested thumbnail time
    public let requestedTime: Double

    /// Actual thumbnail frame time
    public let actualTime: Double

    /// Position of the matching request. Kept internal so file-thumbnail
    /// generation can preserve request-to-URL mapping when callbacks arrive
    /// out of order or another requested frame fails.
    internal let requestIndex: Int
}
