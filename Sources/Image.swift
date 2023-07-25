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
        // Get formats from the file extensions
        let sourcePathFormat = ImageFormat(source.pathExtension)
        let destinationPathFormat = ImageFormat(destination.pathExtension)

        // Read image file
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw CompressionError.failedToReadImage
        }

        // Animated image specific variables
        var animationDuration: Double?
        var animationFrameRate: Int?
        let isAnimationSupportedFormat = settings.format?.isAnimationSupported ?? ((sourcePathFormat?.isAnimationSupported ?? true) && (destinationPathFormat?.isAnimationSupported ?? true))

        var images: [ImageFrame] = []
        var metadata: [CFString: Any]?
        if isAnimationSupportedFormat {
            // Read frames to the `CGImage` array
            let totalFrames = CGImageSourceGetCount(imageSource)
            images.reserveCapacity(totalFrames)
            for index in 0 ..< totalFrames {
                // Get the image
                guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
                    continue
                }
                var frame = ImageFrame(image: cgImage)

                // Frame specific properties
                if let frameProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] {
                    // Source Metadata, retrieve once
                    if !skipMetadata && metadata == nil {
                        metadata = frameProperties
                    }

                    if let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                        frame.delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
                        frame.unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime]  as? Double
                        frame.loopCount = gifProperties[kCGImagePropertyGIFLoopCount] as? Int
                        frame.frameInfoArray = gifProperties[kCGImagePropertyGIFFrameInfoArray] as? [CFDictionary]
                        frame.canvasWidth = gifProperties[kCGImagePropertyGIFCanvasPixelWidth] as? Double
                        frame.canvasHeight = gifProperties[kCGImagePropertyGIFCanvasPixelHeight] as? Double
                    } else if let heicsProperties = frameProperties[kCGImagePropertyHEICSDictionary] as? [CFString: Any] {
                        frame.delayTime = heicsProperties[kCGImagePropertyHEICSDelayTime] as? Double
                        frame.unclampedDelayTime = heicsProperties[kCGImagePropertyHEICSUnclampedDelayTime]  as? Double
                        frame.loopCount = heicsProperties[kCGImagePropertyHEICSLoopCount] as? Int
                        frame.frameInfoArray = heicsProperties[kCGImagePropertyHEICSFrameInfoArray] as? [CFDictionary]
                        frame.canvasWidth = heicsProperties[kCGImagePropertyHEICSCanvasPixelWidth] as? Double
                        frame.canvasHeight = heicsProperties[kCGImagePropertyHEICSCanvasPixelHeight] as? Double
                    } else if #available(macOS 11, iOS 14, tvOS 14, *), let webPProperties = frameProperties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
                        frame.delayTime = webPProperties[kCGImagePropertyWebPDelayTime] as? Double
                        frame.unclampedDelayTime = webPProperties[kCGImagePropertyWebPUnclampedDelayTime]  as? Double
                        frame.loopCount = webPProperties[kCGImagePropertyWebPLoopCount] as? Int
                        frame.frameInfoArray = webPProperties[kCGImagePropertyWebPFrameInfoArray] as? [CFDictionary]
                        frame.canvasWidth = webPProperties[kCGImagePropertyWebPCanvasPixelWidth] as? Double
                        frame.canvasHeight = webPProperties[kCGImagePropertyWebPCanvasPixelHeight] as? Double
                    } else if let pngProperties = frameProperties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
                        frame.delayTime = pngProperties[kCGImagePropertyAPNGDelayTime] as? Double
                        frame.unclampedDelayTime = pngProperties[kCGImagePropertyAPNGUnclampedDelayTime]  as? Double
                        frame.loopCount = pngProperties[kCGImagePropertyAPNGLoopCount] as? Int
                        frame.frameInfoArray = pngProperties[kCGImagePropertyAPNGFrameInfoArray] as? [CFDictionary]
                        frame.canvasWidth = pngProperties[kCGImagePropertyAPNGCanvasPixelWidth] as? Double
                        frame.canvasHeight = pngProperties[kCGImagePropertyAPNGCanvasPixelHeight] as? Double
                    }
                }

                images.append(frame)
            }
            // guard images.count == totalFrames else { Some frames skipped }
        } else {
            // Process as static image, read only first frame
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw CompressionError.emptyImage
            }
            let frame = ImageFrame(image: cgImage)
            images.append(frame)

            // Metadata
            if !skipMetadata, let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                metadata = properties
            }
        }
        guard let first = images.first?.image else { throw CompressionError.emptyImage }

        // Frame Rate, algorithm from the Video.swift is used
        if let frameRate = settings.frameRate, images.count > 1 {
            var duration = 0.0
            for frame in images {
                duration += frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
            }

            if duration != 0.0 {
                animationDuration = duration
                let nominalFrameRate = Double(images.count) / duration
                let nominalFrameRateRounded = Int(nominalFrameRate.rounded())

                if frameRate < nominalFrameRateRounded {
                    let scaleFactor = Double(frameRate) / nominalFrameRate
                    // Find frames which will be written
                    let targetFrames = Int(round(Double(images.count) * scaleFactor))
                    var frames: Set<Int> = []
                    frames.reserveCapacity(targetFrames)
                    // Add first frame index (starting from one)
                    frames.insert(1)
                    // Find other desired frame indexes
                    for index in 1 ..< targetFrames {
                        frames.insert(Int(ceil(Double(images.count) * Double(index) / Double(targetFrames - 1))))
                    }

                    var newImages: [ImageFrame] = []
                    for index in 0 ..< images.count {
                        guard frames.contains(index) else {
                            // Drop the frame
                            continue
                        }

                        // Increase frame delay
                        var frame = images[index]
                        let delay = frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
                        let newDelay = delay * (1.0 / scaleFactor)
                        frame.unclampedDelayTime = newDelay
                        frame.delayTime = min(0.1, round(newDelay * 10.0) / 10.0)

                        // Add the frame
                        newImages.append(frame)
                    }

                    // Update the frames array
                    images = newImages
                    animationFrameRate = frameRate
                } else {
                    animationFrameRate = nominalFrameRateRounded
                }
            } else {
                // Frame rate adjustment isn't possible - source duration is unknown
            }
        }

        var settings = settings
        // When destination format is `nil` use the source image format
        if settings.format == nil {
            if let utType = first.utType, let format = ImageFormat(utType) {
                // Get format from CGImage
                settings.format = format
            } else if let format = destinationPathFormat {
                // File extension format
                settings.format = format
            } else {
                throw CompressionError.unsupportedImageFormat
            }

            // Fix HEIF format based on bit depth
            if settings.format == .heif, first.isHDR {
                settings.format = .heif10
            }
        }

        // Edit
        for index in 0 ..< images.count {
            images[index].image = images[index].image.edit(settings: settings, index: index)
        }

        // Save image to destination in specified `ImageFormat` and `ImageSettings`
        try saveImage(images, at: destination, overwrite: overwrite, settings: settings, metadata: metadata)

        // Delete original
        if deleteSourceFile {
            try? FileManager.default.removeItem(atPath: source.path)
        }

        return ImageInfo(
            format: settings.format!,
            size: CGSize(width: first.width, height: first.height),
            isAnimated: images.count > 1,
            frameRate: animationFrameRate,
            duration: animationDuration
        )
    }

    /// Save `CGImage` to file in `ImageFormat` with `ImageSettings` applying
    public static func saveImage(
        _ frames: [ImageFrame],
        at url: URL,
        overwrite: Bool = false,
        settings: ImageSettings,
        metadata: [CFString: Any]? = nil
    ) throws {
        guard let format = settings.format else { throw CompressionError.unknownImageFormat }
        guard let first = frames.first?.image else { throw CompressionError.emptyImage }

        let embedThumbnail = settings.embedThumbnail ? kCFBooleanTrue! : kCFBooleanFalse!
        let optimizeColors = settings.optimizeColorForSharing ? kCFBooleanTrue! : kCFBooleanFalse!

        switch format {
        case .heif, .heif10:
            // Base options
            var options: [CIImageOption: Any] = [
                .applyOrientationProperty: true
            ]
            // Metadata
            if let metadata = metadata {
                options[.properties] = metadata
            }

            let ciImage = CIImage(cgImage: first, options: options)
            let ciContext = CIContext()

            var optionsDict: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationEmbedThumbnail as String): embedThumbnail,
                CIImageRepresentationOption(rawValue: kCGImageDestinationOptimizeColorForSharing as String): optimizeColors
            ]
            if let quality = settings.quality {
                optionsDict[CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)] = quality
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
        case .jpeg, .gif, .bmp, .ico, .png, .tiff, .heic, .heics:
            // print(CGImageDestinationCopyTypeIdentifiers()) // supported output image formats when using `CGImageDestination` methods
            guard let utType = format.utType, let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, frames.count, nil) else {
                throw CompressionError.failedToCreateImageFile
            }

            var imageOptions: [CFString: Any] = [
                kCGImageDestinationEmbedThumbnail: embedThumbnail,
                kCGImageDestinationOptimizeColorForSharing: optimizeColors
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
                let colorSpace = first.colorSpace ?? CGColorSpaceCreateDeviceRGB()
                let bgraColor = CGColor(colorSpace: colorSpace, components: [blue, green, red, 1.0])
                imageOptions[kCGImageDestinationBackgroundColor] = bgraColor
            }

            // Metadata
            if let metadata = metadata {
                // GPS
                if let gps = metadata[kCGImagePropertyGPSDictionary] {
                    imageOptions[kCGImagePropertyGPSDictionary] = gps
                }

                // Exif
                if let exif = metadata[kCGImagePropertyExifDictionary] {
                    imageOptions[kCGImagePropertyExifDictionary] = exif
                }

                // TIFF
                if let tiff = metadata[kCGImagePropertyTIFFDictionary] {
                    imageOptions[kCGImagePropertyTIFFDictionary] = tiff
                }

                // MakerApple
                if let apple = metadata[kCGImagePropertyMakerAppleDictionary] {
                    imageOptions[kCGImagePropertyMakerAppleDictionary] = apple
                }

                // IPTC
                if let apple = metadata[kCGImagePropertyIPTCDictionary] {
                    imageOptions[kCGImagePropertyIPTCDictionary] = apple
                }
            }

            // Set all frame properties
            CGImageDestinationSetProperties(destination, imageOptions as CFDictionary)

            // Insert all the frames
            for frame in frames {
                let properties: [CFString: Any]?
                switch format {
                case .gif:
                    properties = [
                        kCGImagePropertyGIFDictionary: [
                            kCGImagePropertyGIFDelayTime: frame.delayTime as Any,
                            kCGImagePropertyGIFUnclampedDelayTime: frame.unclampedDelayTime as Any,
                            kCGImagePropertyGIFLoopCount: frame.loopCount as Any,
                            kCGImagePropertyGIFFrameInfoArray: frame.frameInfoArray as Any,
                            kCGImagePropertyGIFCanvasPixelWidth: frame.canvasWidth as Any,
                            kCGImagePropertyGIFCanvasPixelHeight: frame.canvasHeight as Any
                        ] as [CFString: Any]
                    ]
                case .heics:
                    properties = [
                        kCGImagePropertyHEICSDictionary: [
                            kCGImagePropertyHEICSDelayTime: frame.delayTime as Any,
                            kCGImagePropertyHEICSUnclampedDelayTime: frame.unclampedDelayTime as Any,
                            kCGImagePropertyHEICSLoopCount: frame.loopCount as Any,
                            kCGImagePropertyHEICSFrameInfoArray: frame.frameInfoArray as Any,
                            kCGImagePropertyHEICSCanvasPixelWidth: frame.canvasWidth as Any,
                            kCGImagePropertyHEICSCanvasPixelHeight: frame.canvasHeight as Any
                        ] as [CFString: Any]
                    ]
                case .png:
                    properties = [
                        kCGImagePropertyPNGDictionary: [
                            kCGImagePropertyAPNGDelayTime: frame.delayTime as Any,
                            kCGImagePropertyAPNGUnclampedDelayTime: frame.unclampedDelayTime as Any,
                            kCGImagePropertyAPNGLoopCount: frame.loopCount as Any,
                            kCGImagePropertyAPNGFrameInfoArray: frame.frameInfoArray as Any,
                            kCGImagePropertyAPNGCanvasPixelWidth: frame.canvasWidth as Any,
                            kCGImagePropertyAPNGCanvasPixelHeight: frame.canvasHeight as Any
                        ] as [CFString: Any]
                    ]
                default:
                    properties = nil
                }

                CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary?)
            }

            // Write
            if CGImageDestinationFinalize(destination) == false {
                throw CompressionError.failedToSaveImage
            }
        }
    }
}
