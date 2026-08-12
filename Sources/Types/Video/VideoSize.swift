import Foundation

/// Video size data type
public enum CompressionVideoSize {
    /// Original size
    case original

    /// Size to fit video in while preserving aspect ratio, width and height may be rounded to be divisible by 2
    /// On macOS value of 405 may be scalled down to 404, while on iOS stay 405
    /// For best results, always use even number values for width and height when encoding to H.264 or any other format that uses 4:2:0 downsampling
    case fit(CGSize)

    /// Scale video to exact resolution
    case scale(CGSize)

    /// Calculate target resolution based on source video resolution
    case dynamic((_ sourceVideoSize: CGSize) -> CompressionVideoSize)

    /// Get exact value, used for dynamic retreiving
    func value(for videoSize: CGSize) throws -> CompressionVideoSize {
        var size = self
        // Loop while case is dynamic
        var resolutionDepth = 0
        while case .dynamic(let handler) = size {
            guard resolutionDepth < 32 else {
                throw CompressionError.invalidVideoSize
            }
            // Dynamically calculate video size based on source video resolution
            size = handler(videoSize)
            resolutionDepth += 1
        }
        return size
    }
}
