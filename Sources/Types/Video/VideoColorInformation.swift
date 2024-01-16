import AVFoundation

/// Internal type to store color primaries, matrix and transfer function
internal struct VideoColorInformation {
    /// Color Primaries
    let colorPrimaries: String

    /// YCbCr Matrix
    let matrix: String

    /// Transfer Function
    let transferFunction: String

    /// Default initializer
    init(colorPrimaries: String, matrix: String, transferFunction: String) {
        self.colorPrimaries = colorPrimaries
        self.matrix = matrix
        self.transferFunction = transferFunction
    }

    /// Initializer for `CompressionColorPrimary`
    init(for colorProperties: CompressionColorPrimary) {
        switch colorProperties {
        // SD (SMPTE-C)
        case .smpteC:
            colorPrimaries = AVVideoColorPrimaries_SMPTE_C
            matrix = AVVideoYCbCrMatrix_ITU_R_601_4
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
        // SD (PAL)
        case .ebu3213:
            #if os(OSX)
            colorPrimaries = AVVideoColorPrimaries_EBU_3213
            #else
            // Fallback to supported SD color primary
            colorPrimaries = AVVideoColorPrimaries_SMPTE_C
            #endif
            matrix = AVVideoYCbCrMatrix_ITU_R_601_4
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
        // HD | P3
        case .p3D65:
            colorPrimaries = AVVideoColorPrimaries_P3_D65
            matrix = AVVideoYCbCrMatrix_ITU_R_709_2
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
        // HDTV - ITU-R BT.709
        case .itu709_2:
            colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            matrix = AVVideoYCbCrMatrix_ITU_R_709_2
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
        // UHDTV - BT.2020
        case .itu2020:
            colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            matrix = AVVideoYCbCrMatrix_ITU_R_2020
            transferFunction = AVVideoTransferFunction_ITU_R_709_2
        case .itu2020_hlg:
            colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            matrix = AVVideoYCbCrMatrix_ITU_R_2020
            transferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
        case .itu2020_pq:
            colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            matrix = AVVideoYCbCrMatrix_ITU_R_2020
            transferFunction = AVVideoTransferFunction_SMPTE_ST_2084_PQ
        }
    }
}
