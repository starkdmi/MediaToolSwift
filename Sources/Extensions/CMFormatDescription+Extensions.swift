import AVFoundation

/// Public extension for `CMFormatDescription` on `AVAssetTrack`
public extension CMFormatDescription {
    /// Boolean indicator of transparency presence in format description
    var hasAlphaChannel: Bool {
        // Method #1 - Check .containsAlphaChannel extension value
        if let containsAlpha = self.extensions[.containsAlphaChannel] {
            if containsAlpha.propertyListRepresentation as? Int == 1 {
                return true
            }
        }

        // Method #2 - Check pixel format for known alpha channel formats
        let pixelFormat = CMFormatDescriptionGetMediaSubType(self)
        if  pixelFormat == kCVPixelFormatType_32ARGB ||
            pixelFormat == kCVPixelFormatType_32BGRA ||
            pixelFormat == kCVPixelFormatType_32RGBA ||
            pixelFormat == kCVPixelFormatType_32ABGR {
            return true
        }

        // Method #3 - Check kCVImageBufferAlphaChannelModeKey extension value
        let alphaMode = CMFormatDescriptionGetExtension(
            self,
            extensionKey: kCVImageBufferAlphaChannelModeKey
        ) as? String
        if alphaMode == kCVImageBufferAlphaChannelMode_StraightAlpha as String ||
           alphaMode == kCVImageBufferAlphaChannelMode_PremultipliedAlpha as String {
            return true
        }

        // Method #4 - Check kCVPixelFormatContainsAlpha extension value
        if CMFormatDescriptionGetExtension(self, extensionKey: kCVPixelFormatContainsAlpha) as? Bool == true {
            return true
        }

        return false
    }

    /// Boolean indicator of HDR content presence in format description
    var isHDRVideo: Bool {
        guard let transferFunction = CMFormatDescriptionGetExtension(self, extensionKey: kCVImageBufferTransferFunctionKey)
        else { return false }

        return [
            kCVImageBufferTransferFunction_ITU_R_2020,
            kCVImageBufferTransferFunction_ITU_R_2100_HLG,
            kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        ].contains(transferFunction as! CFString) // swiftlint:disable:this force_cast
    }

    /// Video codec value stored in format description
    var videoCodec: AVVideoCodecType {
        let fourCC = CMFormatDescriptionGetMediaSubType(self)
        let fourCCString = String(format: "%c%c%c%c",
            (fourCC >> 24) & 255,
            (fourCC >> 16) & 255,
            (fourCC >> 8) & 255,
            fourCC & 255
        )
        return AVVideoCodecType(rawValue: fourCCString)
    }

    /// Audio format stored in format description
    var audioFormat: AudioFormatID {
        let mediaSubType = CMFormatDescriptionGetMediaSubType(self)
        return AudioFormatID(mediaSubType)
    }
}
