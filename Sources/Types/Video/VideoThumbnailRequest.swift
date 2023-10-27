import Foundation

/// Tuple storing time and corresponding url of video thumbnail
public struct VideoThumbnailRequest {
    /// Public initializer
    public init(time: Double, url: URL) {
        self.time = time
        self.url = url
    }

    /// Thumbnail time
    public let time: Double

    /// Thumbnail destination url
    public let url: URL
}
