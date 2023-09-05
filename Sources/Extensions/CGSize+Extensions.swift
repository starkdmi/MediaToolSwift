import AVFoundation

/// Extensions on `CGSize` providing most common video reolution constants and some image related size operations
public extension CGSize {
    /// Aspect fit resolution for Ultra HD - 3840x2160
    static let uhd = CGSize(width: 3840, height: 3840)

    /// Aspect fit resolution for Full HD - 1920x1080
    static let fhd = CGSize(width: 1920, height: 1920)

    /// Aspect fit resolution for HD - 1280x720
    static let hd = CGSize(width: 1280, height: 1280)

    /// Aspect fit resolution for SD - 640x480
    static let sd = CGSize(width: 640, height: 640)

    /// Aspect fit in new size
    func fit(in size: CGSize) -> CGSize {
        let rect = AVMakeRect(aspectRatio: self, insideRect: CGRect(origin: CGPoint.zero, size: size))
        return rect.size
    }

    /// Oriented size
    internal func oriented(_ orientation: CGImagePropertyOrientation?) -> CGSize {
        let width = self.width
        let height = self.height

        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            return CGSize(width: width, height: height)
        case .leftMirrored, .right, .rightMirrored, .left:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }

    /// Round decimal point
    /*internal var rounded: CGSize {
        return CGSize(
            width: self.width.rounded(),
            height: self.height.rounded()
        )
    }*/

    /// Calculate filled image size after rotation
    internal func rotateFilling(angle: Double) -> CGSize {
        let width = self.width
        let height = self.height

        // Ensure the input size is valid
        guard width > 0 && height > 0 else {
            return .zero
        }

        // Resolve simple cases without calculations
        switch abs(angle).truncatingRemainder(dividingBy: .pi*2) {
        case .zero, .pi: // no rotation or 180-degree flip
            return self
        case .pi/2, .pi * 1.5: // 90 or 270-degree rotation
            return CGSize(width: height, height: width)
        default:
            break
        }

        // Size orientation
        let landscape = width >= height
        let long = landscape ? width : height
        let short = landscape ? height : width

        // Calculate cropping dimensions based on rotation angle
        let sinA = abs(sin(angle))
        let cosA = abs(cos(angle))

        let cropWidth, cropHeight: Double
        if short <= 2.0 * sinA * cosA * long || abs(sinA - cosA) < 1e-10 {
            // Half constrained case: Two crop corners touch the longer side,
            // while the other two corners are on a mid-line parallel to the longer side.
            // This occurs when the rotation angle is close to 0, 90, 180, or 270 degrees.
            let half = 0.5 * short

            // Calculate crop dimensions based on angle and aspect ratio
            cropWidth = landscape ? half / sinA : half / cosA
            cropHeight = landscape ? half / cosA : half / sinA
        } else {
            // Fully constrained case: The crop touches all 4 sides of the rotated rectangle.
            // This happens when the rotation angle is between 45 and 135 degrees, and 225 and 315 degrees.

            // Calculate auxiliary value cos^2(2*angle) for the calculations
            let cos2A = cosA * cosA - sinA * sinA

            // Calculate crop dimensions based on angle, original size, and aspect ratio
            cropWidth = (width * cosA - height * sinA) / cos2A
            cropHeight = (height * cosA - width * sinA) / cos2A
        }

        // Provide rounded cropping dimensions
        return CGSize(width: round(cropWidth), height: round(cropHeight))
    }
}
