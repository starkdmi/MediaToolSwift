/// Video color primary
public enum CompressionColorPrimary {
    /// SD
    case smpteC

    /// SD (PAL), macOS only
    case ebu3213

    /// P3
    case p3D65

    /// HDTV
    case itu709_2

    /// UHDTV SDR
    case itu2020

    /// UHDTV HDR HLG, used by newer iPhone cameras
    case itu2020_hlg

    /// UHDTV HDR PQ
    case itu2020_pq
}
