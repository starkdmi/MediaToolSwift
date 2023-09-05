import CoreImage

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
    let hasAlpha: Bool

    /// HDR data presence
    let isHDR: Bool

    /// Bit depth | bits per component
    // let bitDepth: Int

    /// Image orientation
    var orientation: CGImagePropertyOrientation?

    /// Image frames amount, one for static images
    let framesCount: Int

    /// Animated image frame rate
    let frameRate: Int?

    /// Animated image duration
    let duration: Double?

    /// Animation presence
    var isAnimated: Bool {
        return framesCount > 1
    }
}
