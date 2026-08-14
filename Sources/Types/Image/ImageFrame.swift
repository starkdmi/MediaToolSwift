import Foundation
import CoreImage
import ImageIO

/// Image frame of a static or animated image
public struct ImageFrame: Equatable, Hashable {
    /// A `CGImage` representing frame, operations in`vImage`
    public var cgImage: CGImage?

    /// A `CIImage` representing frame, operations in `CIImage`
    public var ciImage: CIImage?

    /// HDR gain map auxiliary image for HEIF/HEIC formats
    public var gainMap: CIImage?

    /// Flag for additional image resizing
    public var shouldResize: Bool = false

    /// The number of seconds to wait before displaying the next image in an animated sequence, clamped to a minimum of 100 milliseconds
    public var delayTime: Double?

    /// The number of seconds to wait before displaying the next image in an animated sequence
    public var unclampedDelayTime: Double?

    /// The number of times to repeat an animated sequence.
    /// Warning: ImageIO discards the requested value when writing HEICS and
    /// stores a platform constant instead - `0` up to iOS 18/macOS 15, `1` on
    /// the 26 releases - so a HEICS sequence may not round trip its looping.
    public var loopCount: Int?

    /// The width of the main image, in pixels
    public var canvasWidth: Double?

    /// The height of the main image, in pixels
    public var canvasHeight: Double?

    /// An array of dictionaries that contain timing information for the image sequence
    public var frameInfoArray: [CFDictionary]?

    /// Image size
    public var size: CGSize {
        return cgImage?.size ?? ciImage?.extent.size ?? .zero
    }

    /// Canvas size
    public var canvasSize: CGSize? {
        if let width = self.canvasWidth, let height = self.canvasHeight {
            return CGSize(width: width, height: height)
        } else {
            return nil
        }
    }

    /// Scale factor of gain map relative to main image
    public var gainMapScale: CGFloat {
        guard let gainMap = gainMap else { return 1.0 }

        let mainWidth: CGFloat
        if let ciImage = ciImage {
            mainWidth = ciImage.extent.width
        } else if let cgImage = cgImage {
            mainWidth = CGFloat(cgImage.width)
        } else {
            return 1.0
        }

        guard mainWidth > 0 else { return 1.0 }
        return gainMap.extent.width / mainWidth
    }

    /// Load and resize gain map to match loaded image dimensions
    func loadGainMap(url: URL, properties: [CFString: Any]?) -> CIImage? {
        guard #available(macOS 11, iOS 14.1, tvOS 14, visionOS 1, *) else { return nil }

        guard let gainMap = CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true]) else {
            return nil
        }

        // Resize if downsampled
        let originalWidth = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let loadedWidth: CGFloat
        if let ciImage = ciImage {
            loadedWidth = ciImage.extent.width
        } else if let cgImage = cgImage {
            loadedWidth = CGFloat(cgImage.width)
        } else {
            loadedWidth = 0.0
        }

        if originalWidth > 0, loadedWidth > 0, originalWidth > loadedWidth {
            let ratio = loadedWidth / originalWidth
            let size = CGSize(width: gainMap.extent.width * ratio, height: gainMap.extent.height * ratio)
            return gainMap.resizing(to: size)
        }

        return gainMap
    }

    /// Load image frame from file
    internal static func load(
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
            frame.shouldResize = size == nil
        }

        // Retrieve animation properties
        if isAnimated, let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] {
            // Animation info
            if let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                frame.delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
                frame.unclampedDelayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
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

    /// Reads animation-wide repetition metadata. ImageIO exposes this on the
    /// source properties for GIF, HEICS, APNG, and WebP; it is commonly absent
    /// from every individual frame dictionary.
    internal static func sequenceLoopCount(from imageSource: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyProperties(imageSource, nil)
            as? [CFString: Any] else {
            return nil
        }

        func loopCount(dictionaryKey: CFString, valueKey: CFString) -> Int? {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else {
                return nil
            }
            let value: Int?
            if let integer = dictionary[valueKey] as? Int {
                value = integer
            } else if let number = dictionary[valueKey] as? NSNumber {
                value = number.intValue
            } else {
                value = nil
            }
            guard let value, value >= 0 else { return nil }
            return value
        }

        if let value = loopCount(
            dictionaryKey: kCGImagePropertyGIFDictionary,
            valueKey: kCGImagePropertyGIFLoopCount
        ) {
            return value
        }
        if let value = loopCount(
            dictionaryKey: kCGImagePropertyHEICSDictionary,
            valueKey: kCGImagePropertyHEICSLoopCount
        ) {
            return value
        }
        if #available(macOS 11, iOS 14, tvOS 14, visionOS 1, *),
           let value = loopCount(
               dictionaryKey: kCGImagePropertyWebPDictionary,
               valueKey: kCGImagePropertyWebPLoopCount
           ) {
            return value
        }
        return loopCount(
            dictionaryKey: kCGImagePropertyPNGDictionary,
            valueKey: kCGImagePropertyAPNGLoopCount
        )
    }
}

/// Outcome of reducing an animated sequence to a requested frame rate.
internal struct AdjustedFrameRate {
    /// Reduced frames, or `nil` when the sequence was left unchanged.
    let frames: [ImageFrame]?

    /// Frame rate describing the returned sequence.
    let frameRate: Int

    /// The requested primary index remapped onto the returned sequence.
    let primaryIndex: Int
}

internal extension Array where Element == ImageFrame {
    /// Calculate animated image sequence duration
    func validatedDuration() throws -> Double? {
        guard self.count > 1 else { return nil }

        var duration = 0.0
        for frame in self {
            let delay = frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
            guard delay.isFinite, delay >= 0 else {
                throw CompressionError.failedToReadImage
            }

            duration += delay
            guard duration.isFinite else {
                throw CompressionError.failedToReadImage
            }
        }

        return duration > 0.0 ? duration : nil
    }

    /// Adjust animated image sequence frame rate
    /// The algorithm from the Video.swift is used
    func withAdjustedFrameRate(
        frameRate: Int,
        duration: Double,
        primaryIndex: Int
    ) throws -> AdjustedFrameRate {
        guard frameRate > 0,
              duration.isFinite,
              duration > 0,
              indices.contains(primaryIndex) else {
            // Callers reject a non-positive frame rate before reaching this
            // point. Leave the sequence untouched rather than silently moving
            // the primary frame if that guarantee ever changes.
            return AdjustedFrameRate(
                frames: nil,
                frameRate: 0,
                primaryIndex: indices.contains(primaryIndex) ? primaryIndex : 0
            )
        }

        let nominalFrameRate = Double(self.count) / duration
        let roundedNominalFrameRate = nominalFrameRate.rounded()
        guard roundedNominalFrameRate.isFinite,
              roundedNominalFrameRate >= 0,
              roundedNominalFrameRate < Double(Int.max) else {
            throw CompressionError.failedToReadImage
        }
        let nominalFrameRateRounded = Int(roundedNominalFrameRate)

        if frameRate < nominalFrameRateRounded {
            let scaleFactor = Double(frameRate) / nominalFrameRate
            guard scaleFactor.isFinite, scaleFactor > 0 else {
                throw CompressionError.failedToReadImage
            }
            // Find frames which will be written
            // Never round up past the caller's requested frame budget. The
            // legacy pipeline effectively truncated this value, and doing so
            // also avoids producing a sequence faster than requested.
            let requestedFrameBudget = (duration * Double(frameRate)).rounded(.down)
            guard requestedFrameBudget.isFinite, requestedFrameBudget >= 0 else {
                throw CompressionError.failedToReadImage
            }
            let boundedFrameBudget = Swift.min(requestedFrameBudget, Double(self.count))
            let targetFrames = Swift.max(Int(boundedFrameBudget), 1)
            var frames: Set<Int> = []
            frames.reserveCapacity(targetFrames)
            frames.insert(0)
            // Find other desired frame indexes
            if targetFrames > 1 {
                for index in 1 ..< targetFrames {
                    frames.insert(
                        Int(round(Double(self.count - 1) * Double(index) / Double(targetFrames - 1)))
                    )
                }
            }

            // HEIF sequences may designate any frame as primary. Always keep
            // that frame, while preserving the requested output count.
            frames.insert(primaryIndex)
            while frames.count > targetFrames {
                guard let removable = frames
                    .filter({ $0 != primaryIndex })
                    .max(by: {
                        abs($0 - primaryIndex) < abs($1 - primaryIndex)
                    }) else {
                    break
                }
                frames.remove(removable)
            }

            let retainedIndexes = frames.sorted()
            // Repetition is sequence metadata. The caller normalizes it onto
            // one frame before reduction, but that source frame is not
            // necessarily retained when a nonzero HEICS primary frame must
            // win a very small frame budget. Carry the value independently
            // and put it back on the reduced sequence below.
            let sequenceLoopCount = compactMap(\.loopCount).first
            let frameDelays = try map { frame -> Double in
                let delay = frame.unclampedDelayTime ?? frame.delayTime ?? 0.0
                guard delay.isFinite, delay >= 0 else {
                    throw CompressionError.failedToReadImage
                }
                return delay
            }

            var newImages: [ImageFrame] = []
            newImages.reserveCapacity(retainedIndexes.count)
            for (retainedPosition, index) in retainedIndexes.enumerated() {
                // A retained frame remains visible until the next retained
                // frame on the original cyclic timeline. Accumulate every
                // dropped frame's interval instead of scaling only this
                // frame's delay: the latter corrupts variable-rate animation
                // duration and becomes especially visible when a nonzero
                // HEICS primary frame is retained and emitted first.
                let nextIndex = retainedIndexes[(retainedPosition + 1) % retainedIndexes.count]
                var newDelay = 0.0
                var delayIndex = index
                repeat {
                    newDelay += frameDelays[delayIndex]
                    guard newDelay.isFinite else {
                        throw CompressionError.failedToReadImage
                    }
                    delayIndex = (delayIndex + 1) % count
                } while delayIndex != nextIndex

                var frame = self[index]
                frame.unclampedDelayTime = newDelay
                frame.delayTime = Swift.max(0.1, round(newDelay * 10.0) / 10.0)

                // Add the frame
                newImages.append(frame)
            }

            if let sequenceLoopCount, !newImages.isEmpty {
                for index in newImages.indices {
                    newImages[index].loopCount = nil
                }
                newImages[0].loopCount = sequenceLoopCount
            }

            // Return the frames array
            let remappedPrimaryIndex = retainedIndexes.firstIndex(of: primaryIndex) ?? 0
            return AdjustedFrameRate(
                frames: newImages,
                frameRate: frameRate,
                primaryIndex: remappedPrimaryIndex
            )
        } else {
            // Frames weren't changed
            return AdjustedFrameRate(
                frames: nil,
                frameRate: nominalFrameRateRounded,
                primaryIndex: primaryIndex
            )
        }
    }
}
