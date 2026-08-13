import AVFoundation

/// Resolves the output video codec based on source and settings.
internal struct VideoCodecResolver {

    /// Result of codec resolution
    internal struct Resolution {
        /// The resolved output codec
        internal let codec: AVVideoCodecType

        /// Whether alpha channel will be preserved
        internal let preserveAlpha: Bool

        /// Whether the output has alpha channel data
        internal let hasAlpha: Bool

        /// Whether the codec changed from source
        internal let codecChanged: Bool
    }

    /// Supported output video codecs
    internal static var supportedCodecs: [AVVideoCodecType] {
        var codecs: [AVVideoCodecType] = [
            .hevc,
            .hevcWithAlpha,
            .h264,
            .jpeg
        ]
        #if !os(visionOS)
        codecs.append(contentsOf: [
            .proRes422,
            .proRes422LT,
            .proRes422HQ,
            .proRes422Proxy,
            .proRes4444
        ])
        #endif
        return codecs
    }

    internal init() {}

    /// Resolve the output codec
    /// - Parameters:
    ///   - requestedCodec: User-requested codec (nil to use source)
    ///   - sourceCodec: Source video codec
    ///   - sourceHasAlpha: Whether source has alpha channel
    ///   - isHDR: Whether source is HDR
    ///   - preserveAlphaRequested: Whether user wants to preserve alpha
    /// - Returns: Resolution result with final codec settings
    /// - Throws: CompressionError.invalidVideoCodec if codec is not supported
    internal func resolve(
        requestedCodec: AVVideoCodecType?,
        sourceCodec: AVVideoCodecType,
        sourceHasAlpha: Bool,
        isHDR: Bool,
        preserveAlphaRequested: Bool
    ) throws -> Resolution {
        var outputCodec: AVVideoCodecType

        if let requested = requestedCodec {
            outputCodec = requested
        } else {
            // Verify source codec is valid for output
            guard Self.supportedCodecs.contains(sourceCodec) else {
                throw CompressionError.invalidVideoCodec
            }
            outputCodec = sourceCodec
        }

        // HDR videos can't have an alpha channel
        var preserveAlpha = preserveAlphaRequested
        if preserveAlpha, isHDR {
            preserveAlpha = false
        }

        var hasAlpha = false

        // Fix the codec based on alpha support option
        if preserveAlpha {
            if sourceHasAlpha {
                // Fix codec for alpha support
                switch outputCodec {
                case .hevc, .hevcWithAlpha:
                    outputCodec = .hevcWithAlpha
                    hasAlpha = true
                #if !os(visionOS)
                case .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy, .proRes4444:
                    outputCodec = .proRes4444
                    hasAlpha = true
                #endif
                case .h264, .jpeg:
                    // These codecs don't support alpha
                    preserveAlpha = false
                default:
                    break
                }
            } else {
                // Video has no alpha data
                preserveAlpha = false
            }
        } else {
            // Don't store alpha
            if outputCodec == .hevcWithAlpha {
                outputCodec = .hevc
            }
        }

        let codecChanged = outputCodec != sourceCodec

        return Resolution(
            codec: outputCodec,
            preserveAlpha: preserveAlpha,
            hasAlpha: hasAlpha,
            codecChanged: codecChanged
        )
    }
}
