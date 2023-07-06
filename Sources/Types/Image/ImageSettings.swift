import Foundation
import CoreImage

/// Image options
public struct ImageSettings {
    /// Public initializer
    public init(
        format: ImageFormat? = nil,
        size: CGSize? = nil, quality: Double? = nil,
        frameRate: Int? = nil,
        preserveAlphaChannel: Bool = true,
        embedThumbnail: Bool = false,
        optimizeColorForSharing: Bool = false,
        backgroundColor: CGColor? = nil,
        edit: Set<ImageOperation> = []
    ) {
        self.format = format
        self.size = size
        self.quality = quality
        self.frameRate = frameRate
        self.preserveAlphaChannel = preserveAlphaChannel
        self.embedThumbnail = embedThumbnail
        self.optimizeColorForSharing = optimizeColorForSharing
        self.backgroundColor = backgroundColor
        self.edit = edit
    }

    /// Image format, default to source image format
    var format: ImageFormat?

    /// Image resolution to fit in, default to source resolution
    let size: CGSize?

    /// Image quality, from 0.0 to 1.0, not all `ImageFormat` supported
    let quality: Double?

    /// Animated image frame rate
    let frameRate: Int?

    /// Indicates to save alpha channel or drop
    /// Do nothing for images files without alpha channel
    let preserveAlphaChannel: Bool

    /// Embed light version of image to file, JPEG and HEIF only, default to false
    let embedThumbnail: Bool // false

    /// Modify image color space to support older devices, default to false
    let optimizeColorForSharing: Bool // false

    /// Background color for image formats without transparency support, default to white
    let backgroundColor: CGColor?

    /// Image specific operations like crop, filter, atd.
    /// Only one operation of each type is applied
    let edit: Set<ImageOperation>
}
