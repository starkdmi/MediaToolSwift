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

    /// Rejects output choices that cannot preserve a high-bit-depth source.
    /// The pipeline has no SDR tone-mapping stage, so accepting an 8-bit codec
    /// or profile would either fail late or produce video that remains tagged
    /// and reported as HDR after its signal was quantized.
    internal static func validateHighBitDepthCompatibility(
        codec: AVVideoCodecType,
        profile: CompressionVideoProfile?
    ) throws {
        switch codec {
        case .h264, .jpeg:
            throw CompressionError.invalidVideoCodec
        case .hevc:
            switch profile {
            case .hevcMain, .h264Baseline, .h264Main, .h264High:
                throw CompressionError.invalidVideoCodec
            case .value(let value):
                let allowedProfiles = [
                    CompressionVideoProfile.hevcMain10.rawValue,
                    CompressionVideoProfile.hevcMain42210.rawValue
                ]
                guard allowedProfiles.contains(value) else {
                    throw CompressionError.invalidVideoCodec
                }
            case .hevcMain10, .hevcMain42210, .none:
                break
            }
        case .hevcWithAlpha:
            throw CompressionError.invalidVideoCodec
        #if !os(visionOS)
        case .proRes422, .proRes422LT, .proRes422HQ, .proRes422Proxy, .proRes4444:
            break
        #endif
        default:
            throw CompressionError.invalidVideoCodec
        }
    }

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
        preserveAlphaRequested: Bool
    ) throws -> Resolution {
        var outputCodec: AVVideoCodecType

        if let requested = requestedCodec {
            guard Self.supportedCodecs.contains(requested) else {
                throw CompressionError.invalidVideoCodec
            }
            outputCodec = requested
        } else {
            // Verify source codec is valid for output
            guard Self.supportedCodecs.contains(sourceCodec) else {
                throw CompressionError.invalidVideoCodec
            }
            outputCodec = sourceCodec
        }

        var preserveAlpha = preserveAlphaRequested

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
