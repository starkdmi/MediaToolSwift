import AVFoundation

/// Extensions on `CGRect`
internal extension CGRect {
    /// Rectangle which covers all provided points
    init(containing points: [CGPoint]) {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var maxY = CGFloat.leastNormalMagnitude

        // Find the minimum and maximum coordinates of the rotated points
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        // Calculate the dimensions of the enclosing rectangle
        let rectangleWidth = maxX - minX
        let rectangleHeight = maxY - minY

        // Create the CGRect for the enclosing rectangle
        self = CGRect(x: minX, y: minY, width: rectangleWidth, height: rectangleHeight)
    }

    /// Orient `CGRect` to top-left coordinate system based on orientation and size
    func oriented(_ orientation: CGImagePropertyOrientation?, size: CGSize) -> CGRect {
        switch orientation {
        case .up: // 1
            // 0th row at top, 0th column on left
            return self
        case .upMirrored: // 2
            // 0th row at top, 0th column on right - horizontal flip
            return CGRect(
                x: size.width - self.size.width - self.origin.x,
                y: self.origin.y,
                width: self.size.width,
                height: self.size.height
            )
        case .down: // 3
            // 0th row at bottom, 0th column on right - 180 deg rotation
            return CGRect(
                x: size.width - self.size.width - self.origin.x,
                y: size.height - self.size.height - self.origin.y,
                width: self.size.width,
                height: self.size.height
            )
        case .downMirrored: // 4
            // 0th row at bottom, 0th column on left - vertical flip
            return CGRect(
                x: self.origin.x,
                y: size.height - self.size.height - self.origin.y,
                width: self.size.width,
                height: self.size.height
            )
        case .leftMirrored: // 5
            // 0th row on left, 0th column at top -> (y, x, h, w)
            return CGRect(
                x: self.origin.y,
                y: self.origin.x,
                width: self.size.height,
                height: self.size.width
            )
        case .right: // 6
            // 0th row on right, 0th column at top - 90 deg CW
            return self.applying(
                .identity
                    .translatedBy(x: 0, y: size.height)
                    .rotated(by: .pi / -2.0)
            ).rounded
        case .rightMirrored: // 7
            // 0th row on right, 0th column on bottom
            return CGRect(
                x: size.width - self.size.height - self.origin.y,
                y: size.height - self.size.width - self.origin.x,
                width: self.size.height,
                height: self.size.width
            )
        case .left: // 8
            // 0th row on left, 0th column at bottom - 90 deg CCW
            return self.applying(
                .identity
                    .translatedBy(x: size.width, y: 0)
                    .rotated(by: .pi / 2.0)
            ).rounded
        default:
            return self
        }
    }

    /// Oriented rectangle
    /*func oriented(_ orientation: CGImagePropertyOrientation?) -> CGRect {
        guard let orientation = orientation else { return self }

        let origin = self.origin.oriented(orientation)
        let size = self.size.oriented(orientation)

        return CGRect(origin: origin, size: size)
    }*/

    /// Round decimal point
    var rounded: CGRect {
        return CGRect(
            origin: CGPoint(
                x: self.origin.x.rounded(),
                y: self.origin.y.rounded()
            ),
            size: CGSize(
                width: self.size.width.rounded(),
                height: self.size.height.rounded()
            )
        )
    }

    /// Make `CGRect` of specified size with `.zero` origin
    func size(_ size: CGSize) -> CGRect {
        return CGRect(origin: .zero, size: size)
    }

    /// Calculate filled image size after rotation
    func rotateExtended(angle: CGFloat) -> CGRect {
        // Image frame points
        let center = CGPoint(x: self.midX, y: self.midY)
        let topLeft = CGPoint(x: self.minX, y: self.minY)
        let topRight = CGPoint(x: self.maxX, y: self.minY)
        let bottomRight = CGPoint(x: self.maxX, y: self.maxY)
        let bottomLeft = CGPoint(x: self.minX, y: self.maxY)

        // Same points after rotation
        let rotatedTopLeft = topLeft.rotate(by: angle, around: center)
        let rotatedTopRight = topRight.rotate(by: angle, around: center)
        let rotatedBottomRight = bottomRight.rotate(by: angle, around: center)
        let rotatedBottomLeft = bottomLeft.rotate(by: angle, around: center)

        // The minimum rectangle area which covers all rotated points
        let enclosingRectangle = CGRect(containing: [rotatedTopLeft, rotatedTopRight, rotatedBottomRight, rotatedBottomLeft])

        // Calculate extended triangles based on max area and rotated points
        /*let left = rotatedTopLeft.x < rotatedBottomLeft.x ? rotatedTopLeft : rotatedBottomLeft
        let top = rotatedTopRight.y < rotatedTopLeft.y ? rotatedTopRight : rotatedTopLeft
        let right = rotatedTopRight.x > rotatedBottomRight.x ? rotatedTopRight : rotatedBottomRight
        let bottom = rotatedBottomLeft.y > rotatedBottomRight.y ? rotatedBottomLeft : rotatedBottomRight

        let topLeftTriangle = [left, CGPoint(x: enclosingRectangle.minX, y: enclosingRectangle.minY), top]
        let topRightTriangle = [top, CGPoint(x: enclosingRectangle.maxX, y: enclosingRectangle.minY), right]
        let bottomRightTriangle = [right, CGPoint(x: enclosingRectangle.maxX, y: enclosingRectangle.maxY), bottom]
        let bottomLeftTriangle = [bottom, CGPoint(x: enclosingRectangle.minX, y: enclosingRectangle.maxY), left]*/

        return enclosingRectangle
    }

    /*func cgToCIImageRect(height: CGFloat) -> CGRect {
        return CGRect(
            x: self.origin.x,
            y: height - self.size.height - self.origin.y,
            width: self.size.width,
            height: self.size.height
        )
    }*/

    /*func ciToCGImageRect(height: CGFloat) -> CGRect {
        return CGRect(
            x: self.origin.x,
            y: height - self.origin.y - self.size.height,
            width: self.size.width,
            height: self.size.height
        )
    }*/
}
