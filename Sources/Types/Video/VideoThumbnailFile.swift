import Foundation

/// Video thumbnail stored in a file
public struct VideoThumbnailFile {
    /// Thumbnail file url
    let url: URL

    /// Image format
    let format: ImageFormat?

    /// Image resolution
    let size: CGSize

    /// Actual thumbnail frame time
    let time: Double
}
