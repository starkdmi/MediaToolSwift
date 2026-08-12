import CoreImage

/// Image frame of a static or animated image
public enum ImageSize: Equatable {
    /// Original size
    case original

    /// Size to fit in
    case fit(CGSize)

    /// Scale (fill) - no aspect ratio preserving
    // case scale(CGSize)

    /// Cropping size and alignment, `fit` primarly used in video thumbnails
    case crop(fit: CGSize? = nil, options: Crop)

    /// Whether requested dimensions can safely reach integer-backed image
    /// processing APIs.
    internal var hasValidGeometry: Bool {
        switch self {
        case .original:
            return true
        case .fit(let size):
            return size.hasFinitePositiveDimensions
        case .crop(let fit, let options):
            return (fit?.hasFinitePositiveDimensions ?? true) &&
                options.hasValidGeometry
        }
    }

    /// Create scaled ImageSize, all dimensions are multiplied by scale factor
    internal func scaled(by scale: CGFloat) -> ImageSize {
        guard scale != 1.0 else { return self }
        switch self {
        case .original:
            return .original
        case .fit(let size):
            return .fit(CGSize(width: size.width * scale, height: size.height * scale))
        case .crop(let fitSize, let options):
            let scaledFitSize = fitSize.map { CGSize(width: $0.width * scale, height: $0.height * scale) }
            return .crop(fit: scaledFitSize, options: options.scaled(by: scale))
        }
    }

    /// Equatable conformation
    public static func == (lhs: ImageSize, rhs: ImageSize) -> Bool {
        switch (lhs, rhs) {
        case (.original, .original):
            return true
        case (.fit(let lhsSize), .fit(let rhsSize)):
            return lhsSize == rhsSize
        case (let .crop(lhsSize, lhsOptions), let .crop(rhsSize, rhsOptions)):
            return lhsSize == rhsSize && lhsOptions == rhsOptions
        default:
            return false
        }
    }
}
