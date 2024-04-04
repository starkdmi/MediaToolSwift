import AVFoundation

/// Extensions on `AVVideoCodecType`
public extension AVVideoCodecType {
    /// ProRes codec flag
    var isProRes: Bool {
        switch self {
        case .proRes422, .proRes422HQ, .proRes422LT, .proRes422Proxy, .proRes4444:
            true
        default:
            false
        }
    }
}
