import AVFoundation
import Foundation
import CoreMedia
import CoreImage
import ImageIO

/// Image related singletone interface
public struct ImageTool {
    /// Convert image file
    /// - Parameters:
    ///   - source: Input image URL
    ///   - destination: Output image URL
    ///   - settings: Image format options
    ///   - overwrite: Replace destination file if exists, for `false` error will be raised when file already exists
    ///   - deleteSourceFile: Delete source file on success 
    public static func convert(
        source: URL,
        destination: URL,
        settings: ImageSettings = ImageSettings(),
        overwrite: Bool = false,
        deleteSourceFile: Bool = false
    ) async throws -> Bool {
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

        var settings = settings
        // When destination format is `nil` use the source image format
        if settings.format == nil {
            if let format = ImageFormat(source.pathExtension) {
                settings.format = format
            } else {
                throw CompressionError.unsupportedImageFormat
            }
        }

        // Save image to destination in specified `ImageFormat` and `ImageSettings`
        try saveImage(cgImage, at: destination, overwrite: overwrite, settings: settings)

        // Delete original
        if deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return true
    }

    /// Save `CGImage` to file in `ImageFormat` with `ImageSettings` applying
    public static func saveImage(_ image: CGImage, at url: URL, overwrite: Bool = false, settings: ImageSettings) throws {
        guard let format = settings.format else {
            throw CompressionError.unknownImageFormat
        }

        switch format {
        case .heif, .heif10:
            let ciImage = CIImage(cgImage: image)
            let ciContext = CIContext()

            var optionsDict: [CIImageRepresentationOption: Any] = [:]
            if let quality = settings.quality {
                optionsDict = [
                    CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
                ]
            }

            // Pixel format
            let pixelFormat: CIFormat
            switch (image.bitsPerPixel, image.bitsPerComponent) {
            case (32, 32), (32, 64), (32, 128):
                pixelFormat = .RGBAf
            case (16, 32), (16, 64), (32, 32):
                pixelFormat = .RGBAh
            case (32, 16), (16, 16):
                pixelFormat = .RGBA16
            case (32, 8):
                pixelFormat = .RGBA8
            case (16, 8):
                pixelFormat = .RG8
            case (8, 8):
                pixelFormat = .R8
            default:
                pixelFormat = .BGRA8
            }

            var format = settings.format
            var colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            let hasAlpha = image.alphaInfo == CGImageAlphaInfo.first || image.alphaInfo == CGImageAlphaInfo.last // premultiplied skipped
            if hasAlpha {
                // HDR doesn't supported when alpha channel
                if format == .heif10 {
                    format = .heif
                }
            } else {
                // Possible HDR content
                let isHDR = image.bitsPerPixel >= 32 && image.bitsPerComponent >= 8
                if isHDR, format == .heif {
                    format = .heif10

                    let validColorSpace: Bool
                    if #available(macOS 11, iOS 14, tvOS 14, *) {
                        validColorSpace = CGColorSpaceUsesExtendedRange(colorSpace) || CGColorSpaceUsesITUR_2100TF(colorSpace)
                    } else {
                        validColorSpace = CGColorSpaceUsesExtendedRange(colorSpace)
                    }
                    if validColorSpace {
                        // Replace color space with the HDR supported one
                        colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)! // CGColorSpaceCreateExtended(colorSpace)!
                    }
                }
            }

            do {
                switch format {
                case .heif:
                    try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: pixelFormat, colorSpace: colorSpace, options: optionsDict)
                case .heif10:
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
        case .jpeg, .gif, .bmp, .ico, .png, .tiff:
            // print(CGImageDestinationCopyTypeIdentifiers()) // supported output image formats when using `CGImageDestination` methods
            guard let format = format.rawValue, let destination = CGImageDestinationCreateWithURL(url as CFURL, format, 1, nil) else {
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

            CGImageDestinationAddImage(destination, image, imageOptions as CFDictionary)

            if CGImageDestinationFinalize(destination) == false {
                throw CompressionError.failedToSaveImage
            }
        }
    }
}
