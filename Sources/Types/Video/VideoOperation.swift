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

/// Video rotation operation
// public struct Rotate: VideoOperation {}

/// Video crop operation
// public struct Crop: VideoOperation {}
