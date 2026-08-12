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

    internal init() {}

    /// Calculate output video size
    /// - Parameters:
    ///   - settings: Video size setting from configuration
    ///   - sourceSize: Source video size (accounting for orientation)
    ///   - operations: Video operations that may affect size (crop)
    ///   - orientation: Video orientation (for reference, not applied here)
    /// - Returns: Size calculation result
    /// - Throws: CompressionError if crop bounds are invalid
    /// - Note: Orientation transform is NOT applied by this calculator.
    ///         The caller is responsible for applying orientation after determining
    ///         whether video composition is being used.
    internal func calculate(
        settings: CompressionVideoSize,
        sourceSize: CGSize,
        operations: Set<VideoOperation>,
        orientation: VideoOrientation
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

                // Validate crop bounds
                guard rect.origin.x.isFinite,
                      rect.origin.y.isFinite,
                      rect.size.width.isFinite,
                      rect.size.height.isFinite,
                      rect.size.width > 0,
                      rect.size.height > 0,
                      rect.minX >= 0,
                      rect.minY >= 0,
                      rect.maxX <= sourceSize.width,
                      rect.maxY <= sourceSize.height else {
                    throw CompressionError.croppingOutOfBounds
                }

                cropRect = rect
                break
            }
        }

        // Base size after cropping
        var targetSize = cropRect?.size ?? sourceSize
        var resolvedSizeOption = settings
        var needsResize = false

        switch try settings.value(for: sourceSize) {
        case .fit(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                throw CompressionError.invalidVideoSize
            }
            if targetSize.width > size.width || targetSize.height > size.height {
                // Calculate box to fit
                let fittedSize = targetSize.fit(in: size)
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
            if targetSize != size {
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
