import AVFoundation

/// Extensions on `CMFormatDescription` of `AVAssetTrack`
internal extension CMFormatDescription {
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

    /// Video bits per component
    var bitsPerComponent: Int? {
        guard self.mediaType == .video, #available(macOS 12, iOS 15, tvOS 15, *) else { return nil }

        if let value = self.extensions[kCMFormatDescriptionExtension_BitsPerComponent] as? CMFormatDescription.Extensions.Value,
           let number = value.propertyListRepresentation as? Int {
            return number
        }

        return nil
    }

    /// Audio format stored in format description
    var audioFormat: AudioFormatID {
        let mediaSubType = CMFormatDescriptionGetMediaSubType(self)
        return AudioFormatID(mediaSubType)
    }

    /// Video Color Primaries
    var colorPrimaries: String? {
        guard self.mediaType == .video else { return nil }
        if let colorPrimaries = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String {
            return colorPrimaries
        } else if let colorPrimaries = CMFormatDescriptionGetExtension(self, extensionKey: kCVImageBufferColorPrimariesKey) as? String {
            return colorPrimaries
        }
        return nil
    }

    /// Video Color YCbCr Matrix
    var matrix: String? {
        guard self.mediaType == .video else { return nil }
        if let matrix = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String {
            return matrix
        } else if let matrix = CMFormatDescriptionGetExtension(self, extensionKey: kCVImageBufferYCbCrMatrixKey) as? String {
            return matrix
        }
        return nil
    }

    /// Video Color Transfer Function
    var transferFunction: String? {
        guard self.mediaType == .video else { return nil }
        if let transferFunction = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
            return transferFunction
        } else if let transferFunction = CMFormatDescriptionGetExtension(self, extensionKey: kCVImageBufferTransferFunctionKey) as? String {
            return transferFunction
        }
        return nil
    }
}
