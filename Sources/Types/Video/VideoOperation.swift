import CoreMedia

/// Intefrace for operations on video
public protocol VideoOperation {}

/// Cutting video operation
public struct Cut: VideoOperation {
    /// The time to start cutting from, in seconds
    var start: Double

    /// The time to stop the cuttings at, in seconds
    var end: Double

    /// Public initializer using start and end point
    init(from: Double = 0.0, to: Double = .infinity) {
        self.start = max(0.0, from)
        self.end = to
    }

    /// Public initializer using duration
    init(from: Double = 0.0, duration: Double) {
        self.start = max(0.0, from)
        self.end = self.start + duration
    }

    /// Calculate range using start, end points and video duration in seconds
    func getRange(duration: Double, timescale: CMTimeScale) -> CMTimeRange? {
        guard start < duration else { return nil }

        let startTime = CMTime(seconds: start, preferredTimescale: timescale)
        let end = min(duration, self.end)
        let endTime = CMTime(seconds: end, preferredTimescale: timescale)

        /// Start is before the end and the distance is less than duration
        guard start < end, end - start < duration else { return nil }

        return CMTimeRange(start: startTime, end: endTime)
    }
}

/// Custom transformation operation
public enum Transform: VideoOperation {
    /// Rotation
    case rotate(Rotate)

    /// Flip upside down
    case flip

    /// Right to left mirror effect
    case mirror

    /// Raw transform value
    var value: CGAffineTransform {
        switch self {
        case .rotate(let angle):
            return CGAffineTransform(rotationAngle: angle.value)
        case .flip:
            return CGAffineTransform(scaleX: 1.0, y: -1.0)
        case .mirror:
            return CGAffineTransform(scaleX: -1.0, y: 1.0)
        }
    }
}

/// Video rotation operation
public enum Rotate: VideoOperation {
    /// Rotate in a rightward direction
    case clockwise

    /// Rotate in a leftward direction
    case counterclockwise

    /// Custom rotation angle in radians, most likely will be displayed as nearest 90' value
    case angle(Double)

    /// Angle
    var value: Double {
        switch self {
        case .clockwise:
            return .pi/2
        case .counterclockwise:
            return -.pi/2
        case .angle(let radians):
            return radians
        }
    }
}

/// Video crop operation
// public struct Crop: VideoOperation {}
