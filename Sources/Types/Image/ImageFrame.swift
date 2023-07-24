import ImageIO

/// Image frame of a static or animated image
public struct ImageFrame {
    /// A `CGImage` representing frame
    var image: CGImage

    /// The number of seconds to wait before displaying the next image in an animated sequence, clamped to a minimum of 100 milliseconds
    var delayTime: Double?

    /// The number of seconds to wait before displaying the next image in an animated sequence
    var unclampedDelayTime: Double?

    /// The number of times to repeat an animated sequence.
    var loopCount: Int?

    /// The width of the main image, in pixels
    var canvasWidth: Double?

    /// The height of the main image, in pixels
    var canvasHeight: Double?

    /// An array of dictionaries that contain timing information for the image sequence
    var frameInfoArray: [CFDictionary]?
}
