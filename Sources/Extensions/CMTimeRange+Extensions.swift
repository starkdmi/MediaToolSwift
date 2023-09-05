import CoreMedia

/// Extensions on `CMTimeRange`
internal extension CMTimeRange {
    /// Initialize `CMTimeScale` using start and end points, video duration in seconds and time scale
    init?(start: Double, end: Double, duration: Double, timescale: CMTimeScale) {
        guard start < duration else { return nil }

        let from = max(0.0, start)
        let startTime = CMTime(seconds: from, preferredTimescale: timescale)

        let to = min(end, duration)
        let endTime = CMTime(seconds: to, preferredTimescale: timescale)

        /// Start is before the end and the distance is less than duration
        guard from < to, to - from < duration else { return nil }

        self.init(start: startTime, end: endTime)
    }
}
