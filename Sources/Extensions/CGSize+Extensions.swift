import Foundation

/// Public extension on `CGSize` providing most common video reolution constants
public extension CGSize {
    /// Aspect fit resolution for Ultra HD - 3840x2160
    static let uhd = CGSize(width: 3840, height: 3840)

    /// Aspect fit resolution for Full HD - 1920x1080
    static let fhd = CGSize(width: 1920, height: 1920)

    /// Aspect fit resolution for HD - 1280x720
    static let hd = CGSize(width: 1280, height: 1280)

    /// Aspect fit resolution for SD - 640x480
    static let sd = CGSize(width: 640, height: 640)
}
