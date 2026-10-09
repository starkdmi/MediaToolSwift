import AVFoundation
import CoreGraphics

/// Calculates output video size based on settings and source properties.
internal struct VideoSizeCalculator {

    /// Result of size calculation
    internal struct Result {
        /// Target video size
        internal let targetSize: CGSize

        /// The final size option resolved from settings
        internal let resolvedSizeOption: CompressionVideoSize

        /// Whether resizing is needed
        internal let needsResize: Bool

        /// Crop rectangle if cropping is applied
        internal let cropRect: CGRect?
    }

    /// Calculate output video size
    /// - Parameters:
    ///   - settings: Video size setting from configuration
    ///   - sourceSize: Source video size (accounting for orientation)
    ///   - operations: Video operations that may affect size (crop)
    ///   - orientation: Video orientation (for reference, not applied here)
    ///   - displayedSize: Source size with non-square pixel spacing applied. Without
    ///     cropping, fit and scale compare against it, and resize to square pixels.
    /// - Returns: Size calculation result
    /// - Throws: CompressionError if crop bounds are invalid
    /// - Note: Orientation transform is NOT applied by this calculator.
    ///         The caller is responsible for applying orientation after determining
    ///         whether video composition is being used.
    internal func calculate(
        settings: CompressionVideoSize,
        sourceSize: CGSize,
        operations: Set<VideoOperation>,
        orientation: VideoOrientation,
        displayedSize: CGSize? = nil
    ) throws -> Result {
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            throw CompressionError.invalidVideoSize
        }

        for operation in operations {
            if case .rotate(let rotation) = operation,
               !rotation.radians.isFinite {
                throw CompressionError.invalidVideoSize
            }
        }

        // Extract crop rectangle from operations
        var cropRect: CGRect?
        for operation in operations {
            if case .crop(let options) = operation {
                let rect = options.makeCroppingRectangle(in: sourceSize)
                if rect.origin == .zero && rect.size == sourceSize {
                    // Cropping bounds equal to source - no crop needed
                    continue
                }

                // Validate crop bounds. Only the cropping area itself has to fit
                // the source: a rectangle positioned so that it overhangs an
                // edge stays accepted, matching released behavior where the
                // uncovered region is padded rather than rejected.
                guard rect.origin.x.isFinite,
                      rect.origin.y.isFinite,
                      rect.size.width.isFinite,
                      rect.size.height.isFinite,
                      rect.size.width > 0,
                      rect.size.height > 0,
                      rect.minX >= 0,
                      rect.minY >= 0,
                      rect.width <= sourceSize.width,
                      rect.height <= sourceSize.height else {
                    throw CompressionError.croppingOutOfBounds
                }

                cropRect = rect
                break
            }
        }

        // Base size after cropping
        var targetSize = cropRect?.size ?? sourceSize
        // Bounds apply to the displayed picture. Cropping keeps encoded pixels.
        let baseSize = cropRect == nil ? (displayedSize ?? sourceSize) : targetSize
        var resolvedSizeOption = settings
        var needsResize = false

        switch try settings.value(for: cropRect == nil ? baseSize : sourceSize) {
        case .fit(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                throw CompressionError.invalidVideoSize
            }
            if baseSize.width > size.width || baseSize.height > size.height {
                // Calculate box to fit
                let fittedSize = baseSize.fit(in: size)
                // Round to nearest even number
                targetSize = fittedSize.roundEven()
                needsResize = true
            } else {
                resolvedSizeOption = .original
            }

        case .scale(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                throw CompressionError.invalidVideoSize
            }
            if baseSize != size {
                targetSize = size
                needsResize = true
            } else {
                resolvedSizeOption = .original
            }

        case .original:
            break

        default:
            break
        }

        // Orientation is applied after the composition strategy is selected.

        return Result(
            targetSize: targetSize,
            resolvedSizeOption: resolvedSizeOption,
            needsResize: needsResize,
            cropRect: cropRect
        )
    }
}
