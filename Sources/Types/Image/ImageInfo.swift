import Foundation

/// Image info
public struct ImageInfo {
    /// Image format, default to source image format
    let format: ImageFormat

    /// Image resolution to fit in, default to source resolution
    let size: CGSize

    /// File size in kilobytes
    // let filesize: UInt64

    /// Image pixel format
    // let pixelFormat: FourCharCode

    /// Alpha channel presence
    // let hasAlpha: Bool

    /// Animation presence
    let isAnimated: Bool

    /// Animated image frame rate
    let frameRate: Int?

    /// Animated image duration
    let duration: Double?
}
