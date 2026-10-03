import Foundation

/// Video thumbnail stored in a file
public struct VideoThumbnailFile: Sendable {
    /// Thumbnail file url
    public let url: URL

    /// Image format
    public let format: ImageFormat?

    /// Image resolution
    public let size: CGSize

    /// Actual thumbnail frame time
    public let time: Double
}
