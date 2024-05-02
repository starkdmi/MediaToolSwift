import CoreImage

/// Coordinate system origin
/*internal enum CoordinateSystemOrigin {
    /// `CGImage` origin
    case topLeft

    /// `CIImage` origin
    case bottomLeft
}*/

/// Internal extensions on `CGImagePropertyOrientation`
internal extension CGImagePropertyOrientation {
    /// Mirrored property
    var mirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Initialize transform required for coordinates rotation
    /*func transform(in size: CGSize, origin: CoordinateSystemOrigin = .topLeft) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        guard self != .up else { return transform }

        // Rotate
        switch self {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: origin == .topLeft ? 0 : size.height)
            transform = transform.rotated(by: .pi / 2.0)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: origin == .topLeft ? size.height : 0)
            transform = transform.rotated(by: .pi / -2.0)
        default:
            break
        }

        // Mirror
        switch self {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }

        return transform
    }*/

    /*var description: String {
        switch self {
        case .up: return "Up"
        case .upMirrored: return "Up Mirrored"
        case .down: return "Down"
        case .downMirrored: return "Down Mirrored"
        case .left: return "Left"
        case .leftMirrored: return "Left Mirrored"
        case .right: return "Right"
        case .rightMirrored: return "Right Mirrored"
        default: return "Unknown"
        }
    }*/
}
