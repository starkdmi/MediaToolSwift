import AVFoundation
import Foundation
import CoreImage
import ImageIO

/// Image related singletone interface
public struct ImageTool {
    /// Convert image file
    /// - Parameters:
    ///   - source: Input image URL
    ///   - destination: Output image URL
    ///   - settings: Image format options
    ///   - skipMetadata: Whether copy or not source image metadata to destination image file
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on success 
    public static func convert(
        source: URL,
        destination: URL,
        settings: ImageSettings = ImageSettings(),
        skipMetadata: Bool = false,
        overwrite: Bool = false,
        deleteSourceFile: Bool = false
    ) async throws -> ImageInfo {
        // Check the source file exists
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompressionError.sourceFileNotFound
        }
        // print(CGImageSourceCopyTypeIdentifiers()) // supported input image formats using `CGImageDestination`

        // Check the destination location
        if FileManager.default.fileExists(atPath: destination.path) {
            if overwrite {
                do {
                    try FileManager.default.removeItem(atPath: destination.path)
                } catch {
                    throw CompressionError.cannotOverWrite
                }
            } else {
                throw CompressionError.destinationFileExists
            }
        }

        // Read image file to `CGImage
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CompressionError.failedToReadImage
        }

        // Source Metadata
        let properties: [CFString: Any]?
        if !skipMetadata {
            properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        } else {
            properties = nil
        }

        var settings = settings
        // When destination format is `nil` use the source image format
        if settings.format == nil {
            if let utType = cgImage.utType, let format = ImageFormat(utType) {
                // Get format from CGImage
                settings.format = format
            } else if let format = ImageFormat(destination.pathExtension) {
                // Get format from file extension
                settings.format = format
            } else {
                throw CompressionError.unsupportedImageFormat
            }

            // Fix HEIF format based on bit depth
            if settings.format == .heif, cgImage.isHDR {
                settings.format = .heif10
            }
        }

        // Calculate new size (without upscaling)
        var shouldResize = false
        var size = CGSize(width: cgImage.width, height: cgImage.height)
        if let resize = settings.size, size.width > resize.width || size.height > resize.height {
            let rect = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: CGPoint.zero, size: resize))
            size = rect.size
            shouldResize = true
        }

        // Edit
        let image: CGImage
        if !settings.edit.isEmpty || shouldResize {
            image = cgImage.applyingOperations(settings.edit, resize: shouldResize ? size : nil)
        } else {
            image = cgImage
        }

        // Save image to destination in specified `ImageFormat` and `ImageSettings`
        try saveImage(image, at: destination, overwrite: overwrite, settings: settings, properties: properties)

        // Delete original
        if deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return ImageInfo(format: settings.format!, size: CGSize(width: image.width, height: image.height))
    }

    /// Save `CGImage` to file in `ImageFormat` with `ImageSettings` applying
    public static func saveImage(_ image: CGImage, at url: URL, overwrite: Bool = false, settings: ImageSettings, properties: [CFString: Any]? = nil) throws {
        guard let format = settings.format else {
            throw CompressionError.unknownImageFormat
        }

        switch format {
        case .heif, .heif10:
            // Base options
            var options: [CIImageOption: Any] = [
                .applyOrientationProperty: true
            ]
            // Metadata
            if let properties = properties {
                options[.properties] = properties
            }

            let ciImage = CIImage(cgImage: image, options: options)
            let ciContext = CIContext()

            var optionsDict: [CIImageRepresentationOption: Any] = [:]
            if let quality = settings.quality {
                optionsDict = [
                    CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
                ]
            }

            do {
                switch format {
                case .heif:
                    let pixelFormat = CIFormat.RGBA16
                    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

                    try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .heif10:
                    let pixelFormat = CIFormat.RGBA16
                    let colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)!

                    if #available(macOS 12, iOS 15, tvOS 15, *) {
                        try ciContext.writeHEIF10Representation(of: ciImage, to: url, colorSpace: colorSpace, options: optionsDict)
                    } else {
                        // throw CompressionError.failedToCreateImageFile
                        try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                    }
                /*case .jpeg:
                    try ciContext.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: colorSpace, options: optionsDict)
                case .png:
                    try ciContext.writePNGRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .tiff:
                    try ciContext.writeTIFFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)*/
                default:
                    break
                }
            } catch {
                throw CompressionError.failedToSaveImage
            }
        #if os(macOS)
        case .jpeg2000:
            fallthrough
        #endif
        case .jpeg, .gif, .bmp, .ico, .png, .tiff, .heic: // .heics
            // print(CGImageDestinationCopyTypeIdentifiers()) // supported output image formats when using `CGImageDestination` methods
            guard let utType = format.utType, let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
                throw CompressionError.failedToCreateImageFile
            }

            var imageOptions: [CFString: Any] = [
                kCGImageDestinationEmbedThumbnail: settings.embedThumbnail ? kCFBooleanTrue : kCFBooleanFalse,
                kCGImageDestinationOptimizeColorForSharing: settings.optimizeColorForSharing ? kCFBooleanTrue : kCFBooleanFalse
                // kCGImageDestinationImageMaxPixelSize: 256 // use to resize with aspect ratio
            ]

            // Compression quality
            if let quality = settings.quality {
                imageOptions[kCGImageDestinationLossyCompressionQuality] = quality
            }

            // Background color
            if let color = settings.backgroundColor, let components = color.components {
                let red = components[0]
                let green = components[1]
                let blue = components[2]

                // Convert color to BGRA format
                let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                let bgraColor = CGColor(colorSpace: colorSpace, components: [blue, green, red, 1.0])
                imageOptions[kCGImageDestinationBackgroundColor] = bgraColor
            }

            // Metadata
            if let properties = properties {
                // GPS
                if let gps = properties[kCGImagePropertyGPSDictionary] {
                    imageOptions[kCGImagePropertyGPSDictionary] = gps
                }

                // Exif
                if let exif = properties[kCGImagePropertyExifDictionary] {
                    imageOptions[kCGImagePropertyExifDictionary] = exif
                }

                // TIFF
                if let tiff = properties[kCGImagePropertyTIFFDictionary] {
                    imageOptions[kCGImagePropertyTIFFDictionary] = tiff
                }

                // MakerApple
                if let apple = properties[kCGImagePropertyMakerAppleDictionary] {
                    imageOptions[kCGImagePropertyMakerAppleDictionary] = apple
                }

                // IPTC
                if let apple = properties[kCGImagePropertyIPTCDictionary] {
                    imageOptions[kCGImagePropertyIPTCDictionary] = apple
                }
            }

            CGImageDestinationAddImage(destination, image, imageOptions as CFDictionary)

            if CGImageDestinationFinalize(destination) == false {
                throw CompressionError.failedToSaveImage
            }
        }
    }
}
