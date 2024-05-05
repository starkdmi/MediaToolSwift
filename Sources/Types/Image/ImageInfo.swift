import CoreImage

/// Image info
public struct ImageInfo {
    /// Public initializer
    public init(
        format: ImageFormat?,
        size: CGSize,
        hasAlpha: Bool,
        isHDR: Bool,
        bitDepth: Int,
        orientation: CGImagePropertyOrientation? = nil,
        framesCount: Int,
        frameRate: Int? = nil,
        duration: Double? = nil
    ) {
        self.format = format
        self.size = size
        self.hasAlpha = hasAlpha
        self.isHDR = isHDR
        self.bitDepth = bitDepth
        self.orientation = orientation
        self.framesCount = framesCount
        self.frameRate = frameRate
        self.duration = duration
    }

    /// Image format, default to source image format
    public let format: ImageFormat?

    /// Image resolution to fit in, default to source resolution
    public let size: CGSize

    /// File size in kilobytes
    // public let filesize: UInt64

    /// Image pixel format
    // public let pixelFormat: FourCharCode

    /// Alpha channel presence
    public let hasAlpha: Bool

    /// HDR data presence
    public let isHDR: Bool

    /// Bit depth | bits per component
    public let bitDepth: Int

    /// Image orientation
    public var orientation: CGImagePropertyOrientation?

    /// Image frames amount, one for static images
    public let framesCount: Int

    /// Animated image frame rate
    public let frameRate: Int?

    /// Animated image duration
    public let duration: Double?

    /// Animation presence
    public var isAnimated: Bool {
        return framesCount > 1
    }
}
