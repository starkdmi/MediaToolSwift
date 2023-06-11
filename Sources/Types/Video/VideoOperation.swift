import CoreMedia

/// Intefrace for operations on video
public protocol VideoOperation {}

/// Cutting video operation
public struct Cut: VideoOperation {
    /// The time to start cutting from, in seconds
    var startTime: Double?

    /// The time to stop the cuttings at, in seconds
    var endTime: Double?

    /// Public initializer
    init(start: Double?, end: Double?) {
        self.startTime = start
        self.endTime = end
    }

    /// Public initializer using duration
    // init(starTime: Double, duration: Double) { }

    /// Calculate range using startTime, endTime and video duration in seconds
    func getRange(duration: Double, timescale: CMTimeScale) -> CMTimeRange? {
        // One of the parameters shouln't be nil
        guard startTime != nil || endTime != nil else { return nil }

        var start: CMTime?
        if let startTime = startTime, startTime > 0.0 && startTime < duration {
            start = CMTime(seconds: startTime, preferredTimescale: timescale)
        }

        var end: CMTime?
        if let endTime = endTime, endTime <= duration {
            end = CMTime(seconds: endTime, preferredTimescale: timescale)
        }

        if let start = start, let end = end {
            // End should be greater than start
            guard endTime! > startTime! else { return nil }

            return CMTimeRange(start: start, end: end)
        } else if let start = start {
            let end = CMTime(seconds: duration, preferredTimescale: timescale)
            return CMTimeRange(start: start, end: end)
        } else if let end = end {
            return CMTimeRange(start: CMTime.zero, end: end)
        }

        return nil
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
