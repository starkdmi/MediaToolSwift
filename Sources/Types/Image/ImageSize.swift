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
