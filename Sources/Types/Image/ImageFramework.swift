import Foundation

/// Image framework
public enum ImageFramework {
    /// Accelerate
    case vImage

    /// Core Graphics
    case cgImage

    /// Core Image
    case ciImage

    internal static func animatedFramework(
        isHDR: Bool,
        hasAlpha: Bool,
        preserveAlphaChannel: Bool,
        isRotationByCustomAngle: Bool,
        preferredFramework: ImageFramework
    ) -> ImageFramework {
        return (preserveAlphaChannel && hasAlpha && isRotationByCustomAngle) || preferredFramework == .cgImage || isHDR ? .cgImage : .vImage
    }

    /// Find framework suitable for image processing (editing)
    internal static func processingFramework(
        isHDR: Bool,
        hasAlpha: Bool,
        preserveAlphaChannel: Bool,
        isLowQuality: Bool,
        isAnimated: Bool,
        isRotationByCustomAngle: Bool, // rotation angle is not 90 degree multiply
        preferredFramework: ImageFramework
    ) -> ImageFramework {
        let preferCG = preferredFramework == .cgImage
        let preferCI = preferredFramework == .ciImage

        if preferCI, isLowQuality {
            // `CIImage` produce bad quality (usually) or invalid data (for HDR) while output format is GIF, JPEG2000
            return .cgImage
        }

        if isAnimated {
            // Animated images, CGImage or vImage
            return animatedFramework(
                isHDR: isHDR,
                hasAlpha: hasAlpha,
                preserveAlphaChannel: preserveAlphaChannel,
                isRotationByCustomAngle: isRotationByCustomAngle,
                preferredFramework: preferredFramework
            )
        } else {
            // Static images
            if isHDR {
                // HDR images, always use CIImage
                return .ciImage
            } else if hasAlpha {
                // Alpha channel (transparent) images
                if preferCI {
                    return .ciImage
                }

                // Prefer `CGImage` over the `vImage` on custom angle rotation
                return (preserveAlphaChannel && isRotationByCustomAngle) || preferCG ? .cgImage : .vImage
            } else {
                // Any other static image
                switch preferredFramework {
                case .ciImage: return .ciImage
                case .vImage: return .vImage
                case .cgImage: return .cgImage
                }
            }
        }
    }
}

/// Image loading algorithms, used to determine how image will be loaded from file
internal enum ImageLoadingMethod: Equatable {
    case ciImage, cgImageFull, cgImageThumb(CGSize?)

    static func select(
        preferredFramework: ImageFramework,
        isHDR: Bool,
        isWebP: Bool,
        isLowQuality: Bool,
        isAnimated: Bool,
        hasAlpha: Bool,
        preserveAlphaChannel: Bool,
        isRotationByCustomAngle: Bool,
        fitSize: CGSize?
    ) -> ImageLoadingMethod {
        if isWebP {
            return .cgImageThumb(nil)
        }

        if preferredFramework == .ciImage, isLowQuality {
            // `CIImage` produce bad quality (usually) or invalid data (for HDR) while output format is GIF, JPEG2000
            return .cgImageThumb(nil)
        }

        if isHDR {
            return isAnimated ? .cgImageFull : .ciImage
        } else {
            switch preferredFramework {
            case .vImage:
                if hasAlpha && preserveAlphaChannel && isRotationByCustomAngle {
                    // `CGImage` with alpha channel should be loaded as thumb to be supported by `CGContext`
                    return .cgImageThumb(nil)
                } else if let fitSize = fitSize {
                    return .cgImageThumb(fitSize)
                } else {
                    return .cgImageFull
                }
            case .cgImage:
                // `CGImage` loaded always as a thumb so it will be already in supported by `CGContext` format
                return .cgImageThumb(nil)
            case .ciImage:
                return .ciImage
            }
        }
    }

    /// Equatable conformance
    public static func == (lhs: ImageLoadingMethod, rhs: ImageLoadingMethod) -> Bool {
        switch (lhs, rhs) {
        case (.cgImageThumb(let lhsSize), .cgImageThumb(let rhsSize)):
            return lhsSize == rhsSize
        case (.cgImageFull, .cgImageFull):
            return true
        case (.ciImage, .ciImage):
            return true
        default:
            return false
        }
    }
}
