import Foundation
import CoreImage

/// Image frame of a static or animated image
internal struct ImageFrame: Equatable, Hashable {
    /// A `CGImage` representing frame, operations in`vImage`
    var cgImage: CGImage?

    /// A `CIImage` representing frame, operations in `CIImage`
    var ciImage: CIImage?

    /// Flag for additional image resizing
    var shouldResize: Bool = false

    /// The number of seconds to wait before displaying the next image in an animated sequence, clamped to a minimum of 100 milliseconds
    var delayTime: Double?

    /// The number of seconds to wait before displaying the next image in an animated sequence
    var unclampedDelayTime: Double?

    /// The number of times to repeat an animated sequence.
    var loopCount: Int?

    /// The width of the main image, in pixels
    var canvasWidth: Double?

    /// The height of the main image, in pixels
    var canvasHeight: Double?

    /// An array of dictionaries that contain timing information for the image sequence
    var frameInfoArray: [CFDictionary]?

    /// Image size
    var size: CGSize {
        return cgImage?.size ?? ciImage?.extent.size ?? .zero
    }

    /// Canvas size
    var canvasSize: CGSize? {
        if let width = self.canvasWidth, let height = self.canvasHeight {
            return CGSize(width: width, height: height)
        } else {
            return nil
        }
    }

    /// Load image frame from file
    static func load(
        url: URL,
        imageSource: CGImageSource,
        index: Int,
        method: ImageLoadingMethod,
        isAnimated: Bool
    ) throws -> ImageFrame {
        lazy var frame = ImageFrame()

        switch method {
        case .ciImage:
            // Load full `CIImage`
            let options: [CIImageOption: Any]? = [
                .applyOrientationProperty: false
            ]
            guard let ciImage = CIImage(contentsOf: url, options: options) else {
                throw CompressionError.failedToReadImage
            }

            // No animation possible, return the frame
            return ImageFrame(ciImage: ciImage, shouldResize: true) // shouldResize - full image loaded
        case .cgImageFull:
            // Load full `CGImage`
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true
                // kCGImageSourceShouldAllowFloat: kCFBooleanTrue
            ]
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, index, options as CFDictionary)
            guard cgImage != nil else { throw CompressionError.failedToReadImage }

            frame.cgImage = cgImage
            frame.shouldResize = true
        case .cgImageThumb(let size):
            // Resize using ImageIO thumbnails API
            // The resulting image have different pixel format compared to `CGImageSourceCreateImageAtIndex`
            var options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: false,
                kCGImageSourceShouldCacheImmediately: true
                // kCGImageSourceShouldAllowFloat: kCFBooleanTrue
            ]

            // Thumbnail size
            if let size = size {
                options[kCGImageSourceThumbnailMaxPixelSize] = max(size.width, size.height)
            }

            // Get `CGImage`
            let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary)
            guard cgImage != nil else { throw CompressionError.failedToReadImage }

            frame.cgImage = cgImage
            frame.shouldResize = false
        }

        // Retrieve animation properties
        if isAnimated, let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] {
            // Animation info
            if let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                frame.delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
                frame.unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime]  as? Double
                frame.loopCount = gifProperties[kCGImagePropertyGIFLoopCount] as? Int
                frame.frameInfoArray = gifProperties[kCGImagePropertyGIFFrameInfoArray] as? [CFDictionary]
                frame.canvasWidth = gifProperties[kCGImagePropertyGIFCanvasPixelWidth] as? Double
                frame.canvasHeight = gifProperties[kCGImagePropertyGIFCanvasPixelHeight] as? Double
            } else if let heicsProperties = properties[kCGImagePropertyHEICSDictionary] as? [CFString: Any] {
                frame.delayTime = heicsProperties[kCGImagePropertyHEICSDelayTime] as? Double
                frame.unclampedDelayTime = heicsProperties[kCGImagePropertyHEICSUnclampedDelayTime]  as? Double
                frame.loopCount = heicsProperties[kCGImagePropertyHEICSLoopCount] as? Int
                frame.frameInfoArray = heicsProperties[kCGImagePropertyHEICSFrameInfoArray] as? [CFDictionary]
                frame.canvasWidth = heicsProperties[kCGImagePropertyHEICSCanvasPixelWidth] as? Double
                frame.canvasHeight = heicsProperties[kCGImagePropertyHEICSCanvasPixelHeight] as? Double
            } else if #available(macOS 11, iOS 14, tvOS 14, *), let webPProperties = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
                frame.delayTime = webPProperties[kCGImagePropertyWebPDelayTime] as? Double
                frame.unclampedDelayTime = webPProperties[kCGImagePropertyWebPUnclampedDelayTime]  as? Double
                frame.loopCount = webPProperties[kCGImagePropertyWebPLoopCount] as? Int
                frame.frameInfoArray = webPProperties[kCGImagePropertyWebPFrameInfoArray] as? [CFDictionary]
                frame.canvasWidth = webPProperties[kCGImagePropertyWebPCanvasPixelWidth] as? Double
                frame.canvasHeight = webPProperties[kCGImagePropertyWebPCanvasPixelHeight] as? Double
            } else if let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
                frame.delayTime = pngProperties[kCGImagePropertyAPNGDelayTime] as? Double
                frame.unclampedDelayTime = pngProperties[kCGImagePropertyAPNGUnclampedDelayTime]  as? Double
                frame.loopCount = pngProperties[kCGImagePropertyAPNGLoopCount] as? Int
                frame.frameInfoArray = pngProperties[kCGImagePropertyAPNGFrameInfoArray] as? [CFDictionary]
                frame.canvasWidth = pngProperties[kCGImagePropertyAPNGCanvasPixelWidth] as? Double
                frame.canvasHeight = pngProperties[kCGImagePropertyAPNGCanvasPixelHeight] as? Double
            }
        }

        return frame
    }
}

internal extension Array where Element == ImageFrame {
    /// Calculate animated image sequence duration
    var duration: Double? {
        guard self.count > 1 else { return nil }

        var duration = 0.0
        for frame in self {
            duration += frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
        }

        return duration > 0.0 ? duration : nil
    }

    /// Adjust animated image sequence frame rate
    /// The algorithm from the Video.swift is used
    func withAdjustedFrameRate(frameRate: Int, duration: Double) -> (frames: [ImageFrame]?, frameRate: Int) {
        let nominalFrameRate = Double(self.count) / duration
        let nominalFrameRateRounded = Int(nominalFrameRate.rounded())

        if frameRate < nominalFrameRateRounded {
            let scaleFactor = Double(frameRate) / nominalFrameRate
            // Find frames which will be written
            let targetFrames = Int(round(Double(self.count) * scaleFactor))
            var frames: Set<Int> = []
            frames.reserveCapacity(targetFrames)
            // Add first frame index (starting from one)
            frames.insert(1)
            // Find other desired frame indexes
            for index in 1 ..< targetFrames {
                frames.insert(Int(ceil(Double(self.count) * Double(index) / Double(targetFrames - 1))))
            }

            var newImages: [ImageFrame] = []
            for index in 0 ..< self.count {
                guard frames.contains(index) else {
                    // Drop the frame
                    continue
                }

                // Increase frame delay
                var frame = self[index]
                let delay = frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
                let newDelay = delay * (1.0 / scaleFactor)
                frame.unclampedDelayTime = newDelay
                frame.delayTime = Swift.min(0.1, round(newDelay * 10.0) / 10.0)

                // Add the frame
                newImages.append(frame)
            }

            // Return the frames array
            return (newImages, frameRate)
        } else {
            // Frames weren't changed
            return (nil, nominalFrameRateRounded)
        }
    }
}
