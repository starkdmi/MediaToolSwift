import AVFoundation

/// Video thumbnail as `CGImage`
public struct VideoThumbnail {
    /// Thumbnail image
    let image: CGImage

    /// Requested thumbnail time
    let requestedTime: Double

    /// Actual thumbnail frame time
    let actualTime: Double
}
