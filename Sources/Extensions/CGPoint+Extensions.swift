import AVFoundation

/// Extensions on `CGPoint`
internal extension CGPoint {
    /// Rotate point relative to another point
    func rotate(by angle: CGFloat, around center: CGPoint) -> CGPoint {
        let translatedPoint = CGPoint(x: self.x - center.x, y: self.y - center.y)

        let rotatedX = translatedPoint.x * cos(angle) - translatedPoint.y * sin(angle) + center.x
        let rotatedY = translatedPoint.x * sin(angle) + translatedPoint.y * cos(angle) + center.y

        return CGPoint(x: rotatedX, y: rotatedY)
    }

    /// Oriented point
    func oriented(_ orientation: CGImagePropertyOrientation?) -> CGPoint {
        let width = self.x
        let height = self.y

        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            return CGPoint(x: width, y: height)
        case .leftMirrored, .right, .rightMirrored, .left:
            return CGPoint(x: height, y: width)
        default:
            return CGPoint(x: width, y: height)
        }
    }
}
