import Foundation
import CoreImage

/// Image options
public struct ImageSettings {
    /// Public initializer
    public init(
        format: ImageFormat? = nil,
        size: ImageSize = .original,
        quality: Double? = nil,
        frameRate: Int? = nil,
        skipAnimation: Bool = false,
        preserveAlphaChannel: Bool = true,
        embedThumbnail: Bool = false,
        optimizeColorForSharing: Bool = false,
        backgroundColor: CGColor? = nil,
        edit: Set<ImageOperation> = [],
        preferredFramework: ImageFramework = .ciImage
    ) {
        self.format = format
        self.size = size
        self.quality = quality
        self.frameRate = frameRate
        self.skipAnimation = skipAnimation
        self.preserveAlphaChannel = preserveAlphaChannel
        self.embedThumbnail = embedThumbnail
        self.optimizeColorForSharing = optimizeColorForSharing
        self.backgroundColor = backgroundColor
        self.edit = edit
        self.preferredFramework = preferredFramework
    }

    /// Image format, default to source image format
    var format: ImageFormat?

    /// Image size and crop options, default to source resolution
    var size: ImageSize

    /// Image quality, from 0.0 to 1.0 where 1.0 is lossless, not all `ImageFormat` supported
    var quality: Double?

    /// Animated image frame rate
    var frameRate: Int?

    /// Preserve only main (HEIF) or first frame of animated image
    var skipAnimation: Bool

    /// Indicates to save alpha channel or drop
    /// Do nothing for images files without alpha channel
    var preserveAlphaChannel: Bool

    /// Embed light version of image to file, JPEG and HEIF only, default to false
    var embedThumbnail: Bool

    /// Modify image color space to support older devices, default to false
    var optimizeColorForSharing: Bool

    /// Background color for image formats without transparency support, default to white
    var backgroundColor: CGColor?

    /// Image specific operations like crop, filter, atd.
    /// Only one operation of each type is applied
    var edit: Set<ImageOperation>

    /// Image framework used for loading, editing and saving
    /// Not always taken into account
    var preferredFramework: ImageFramework
}
