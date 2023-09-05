import CoreImage

internal enum ImagePixelFormat {
    case abgr
    case argb
    case bgra
    case rgba
}

internal extension CGBitmapInfo {
    /// Get the channels order
    var pixelFormat: ImagePixelFormat? {
        let alphaInfo = CGImageAlphaInfo(rawValue: self.rawValue & type(of: self).alphaInfoMask.rawValue)
        let alphaFirst = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst
        let alphaLast = alphaInfo == .premultipliedLast || alphaInfo == .last || alphaInfo == .noneSkipLast
        let endianLittle = self.contains(.byteOrder16Little) || self.contains(.byteOrder32Little)

        if alphaFirst && endianLittle {
            return .bgra
        } else if alphaFirst {
            return .argb
        } else if alphaLast && endianLittle {
            return .abgr
        } else if alphaLast {
            return .rgba
        } else {
            return nil
        }
    }
}
