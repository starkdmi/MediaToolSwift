import Foundation
import CoreImage

public extension CGImage {
    /// Alpha channel presence
    /// Warning: Premultiplied alpha is skipped here
    var hasAlpha: Bool {
        return alphaInfo == CGImageAlphaInfo.first || alphaInfo == CGImageAlphaInfo.last
    }

    /// HDR data presence
    var isHDR: Bool {
        var hdrColorSpace = true
        if let colorSpace = self.colorSpace {
            if #available(macOS 11, iOS 14, tvOS 14, *) {
                if CGColorSpaceUsesExtendedRange(colorSpace) || CGColorSpaceUsesITUR_2100TF(colorSpace) {
                    hdrColorSpace = true
                } else {
                    hdrColorSpace = false
                }
            } else if CGColorSpaceUsesExtendedRange(colorSpace) {
                hdrColorSpace = true
            } else {
                hdrColorSpace = false
            }
        }

        return bitsPerComponent > 8 && hdrColorSpace
    }
}
