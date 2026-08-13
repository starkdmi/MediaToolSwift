import AVFoundation
import AudioToolbox

/// Resolves audio codec settings and creates encoder parameters
/// Shared by the audio-only and video conversion configuration paths.
internal struct AudioCodecResolver {

    /// Result of audio codec resolution
    ///
    internal struct Resolution {
        /// The resolved output codec
        internal let codec: CompressionAudioCodec

        /// Whether the codec changed from source
        internal let codecChanged: Bool

        /// Whether any settings changed requiring re-encoding
        internal let hasChanges: Bool

        /// Target bitrate (nil = use encoder default)
        internal let targetBitrate: Int?

        /// Encoder parameters dictionary
        internal let encoderParameters: [String: Any]?

        /// Decoder (reader) settings dictionary
        internal let decoderSettings: [String: Any]?
    }

    /// Resolve audio codec and settings
    /// - Parameters:
    ///   - settings: User audio settings (nil = passthrough)
    ///   - sourceAnalysis: Source track analysis
    ///   - calculatedBitsPerChannel: Pre-calculated bits per channel (from AudioTrackAnalyzer.calculateBitsPerChannel)
    ///                               When source bitsPerChannel is 0, this should be used instead
    /// - Returns: Resolution result with codec settings
    internal func resolve(
        settings: CompressionAudioSettings?,
        sourceAnalysis: AudioTrackAnalyzer.Analysis,
        calculatedBitsPerChannel: Int? = nil
    ) -> Resolution {
        guard let settings = settings else {
            // No settings = passthrough
            return Resolution(
                codec: sourceAnalysis.codec,
                codecChanged: false,
                hasChanges: false,
                targetBitrate: nil,
                encoderParameters: nil,
                decoderSettings: nil
            )
        }

        // Use calculated bitsPerChannel if source doesn't provide it
        let effectiveBitsPerChannel: Int
        if sourceAnalysis.bitsPerChannel > 0 {
            effectiveBitsPerChannel = sourceAnalysis.bitsPerChannel
        } else if let calculated = calculatedBitsPerChannel, calculated > 0 {
            effectiveBitsPerChannel = calculated
        } else {
            effectiveBitsPerChannel = 16 // Ultimate fallback
        }

        // Resolve codec
        var codec = settings.codec
        if codec == .default {
            if let sourceCodec = CompressionAudioCodec(formatId: sourceAnalysis.formatId),
               sourceCodec != .default {
                codec = sourceCodec
            } else {
                // AVAssetWriter cannot passthrough decoded PCM into an unknown
                // source codec. AAC is the portable default for explicit
                // settings applied to MP3/E-AC-3 and other unsupported inputs.
                codec = .aac
            }
        }

        let codecChanged = sourceAnalysis.formatId != codec.formatId
        var targetBitrate: Int?
        var encoderParameters: [String: Any]?

        // Build encoder parameters based on codec
        switch codec {
        case .aac:
            encoderParameters = buildAACParameters(
                settings: settings,
                sampleRate: sourceAnalysis.sampleRate,
                channels: sourceAnalysis.channelsPerFrame,
                targetBitrate: &targetBitrate
            )

        case .opus:
            encoderParameters = buildOpusParameters(
                settings: settings,
                sampleRate: sourceAnalysis.sampleRate,
                channels: sourceAnalysis.channelsPerFrame,
                targetBitrate: &targetBitrate
            )

        case .flac:
            encoderParameters = buildFLACParameters(
                settings: settings,
                sampleRate: sourceAnalysis.sampleRate,
                channels: sourceAnalysis.channelsPerFrame
            )

        case .lpcm:
            encoderParameters = buildLPCMParameters(
                settings: settings,
                sampleRate: sourceAnalysis.sampleRate,
                channels: sourceAnalysis.channelsPerFrame,
                bitsPerChannel: effectiveBitsPerChannel,
                isFloat: sourceAnalysis.isFloat,
                isBigEndian: sourceAnalysis.isBigEndian
            )

        case .alac:
            encoderParameters = buildALACParameters(
                settings: settings,
                sampleRate: sourceAnalysis.sampleRate,
                channels: sourceAnalysis.channelsPerFrame,
                bitsPerChannel: effectiveBitsPerChannel
            )

        case .default:
            // Passthrough
            break
        }

        // Build decoder settings if needed
        let decoderSettings = buildDecoderSettings(
            settings: settings,
            sourceAnalysis: sourceAnalysis,
            effectiveBitsPerChannel: effectiveBitsPerChannel
        )

        // Detect if changes require re-encoding
        let bitrateChanged = detectBitrateChange(
            codecChanged: codecChanged,
            targetBitrate: targetBitrate,
            sourceBitrate: sourceAnalysis.estimatedBitrate
        )

        let defaultSettings = CompressionAudioSettings()
        let hasChanges = codecChanged ||
            bitrateChanged ||
            ((sourceAnalysis.formatId == kAudioFormatMPEG4AAC || sourceAnalysis.formatId == kAudioFormatFLAC) &&
             settings.quality != defaultSettings.quality) ||
            settings.sampleRate != defaultSettings.sampleRate

        return Resolution(
            codec: codec,
            codecChanged: codecChanged,
            hasChanges: hasChanges,
            targetBitrate: targetBitrate,
            encoderParameters: hasChanges ? encoderParameters : nil,
            decoderSettings: hasChanges ? decoderSettings : nil
        )
    }

    // MARK: - Private Helpers

    private func buildAACParameters(
        settings: CompressionAudioSettings,
        sampleRate: Int,
        channels: Int,
        targetBitrate: inout Int?
    ) -> [String: Any] {
        var channelLayout = AudioChannelLayout()
        switch channels {
        case 1:
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case 2:
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_2_0
        case 6:
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_A
        case 8:
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_7_1_A
        default:
            // Keep the discrete channel count without silently forcing stereo.
            channelLayout.mChannelLayoutTag = AudioChannelLayoutTag(
                kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
            )
        }
        let channelLayoutData = NSData(bytes: &channelLayout, length: MemoryLayout.size(ofValue: channelLayout))

        var params: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.sampleRate ?? sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: channelLayoutData
        ]

        if case .value(let bitrate) = settings.bitrate {
            // MPEG4AAC valid bitrate range is [64, 320]
            let clampedBitrate: Int
            if bitrate < 64000 {
                clampedBitrate = 64000
            } else if bitrate > 320_000 {
                clampedBitrate = 320_000
            } else {
                clampedBitrate = bitrate
            }
            params[AVEncoderBitRateKey] = clampedBitrate
            targetBitrate = clampedBitrate
        }

        if let quality = settings.quality {
            params[AVEncoderAudioQualityKey] = quality.rawValue
        }

        return params
    }

    private func buildOpusParameters(
        settings: CompressionAudioSettings,
        sampleRate: Int,
        channels: Int,
        targetBitrate: inout Int?
    ) -> [String: Any] {
        let supportedRates = [8_000, 12_000, 16_000, 24_000, 48_000]
        let requestedRate = settings.sampleRate ?? sampleRate
        let outputRate = supportedRates.min {
            abs($0 - requestedRate) < abs($1 - requestedRate)
        } ?? 48_000
        var params: [String: Any] = [
            AVFormatIDKey: kAudioFormatOpus,
            AVSampleRateKey: outputRate,
            AVNumberOfChannelsKey: channels
        ]

        if case .value(let bitrate) = settings.bitrate {
            // Opus valid bitrate range is [2, 510]
            let clampedBitrate: Int
            if bitrate < 2000 {
                clampedBitrate = 2000
            } else if bitrate > 510_000 {
                clampedBitrate = 510_000
            } else {
                clampedBitrate = bitrate
            }
            params[AVEncoderBitRateKey] = clampedBitrate
            targetBitrate = clampedBitrate
        }

        return params
    }

    private func buildFLACParameters(
        settings: CompressionAudioSettings,
        sampleRate: Int,
        channels: Int
    ) -> [String: Any] {
        var params: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: settings.sampleRate ?? sampleRate,
            AVNumberOfChannelsKey: channels
        ]

        if let quality = settings.quality {
            params[AVEncoderAudioQualityKey] = quality.rawValue
        }

        return params
    }

    private func buildLPCMParameters(
        settings: CompressionAudioSettings,
        sampleRate: Int,
        channels: Int,
        bitsPerChannel: Int,
        isFloat: Bool,
        isBigEndian: Bool
    ) -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: settings.sampleRate ?? sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitsPerChannel > 0 ? bitsPerChannel : 16,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private func buildALACParameters(
        settings: CompressionAudioSettings,
        sampleRate: Int,
        channels: Int,
        bitsPerChannel: Int
    ) -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: settings.sampleRate ?? sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitDepthHintKey: bitsPerChannel > 0 ? bitsPerChannel : 16
        ]
    }

    private func buildDecoderSettings(
        settings: CompressionAudioSettings,
        sourceAnalysis: AudioTrackAnalyzer.Analysis,
        effectiveBitsPerChannel: Int
    ) -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: settings.sampleRate ?? sourceAnalysis.sampleRate,
            AVNumberOfChannelsKey: sourceAnalysis.channelsPerFrame,
            AVLinearPCMBitDepthKey: effectiveBitsPerChannel,
            AVLinearPCMIsFloatKey: sourceAnalysis.isFloat,
            AVLinearPCMIsBigEndianKey: sourceAnalysis.isBigEndian
        ]
    }

    private func detectBitrateChange(
        codecChanged: Bool,
        targetBitrate: Int?,
        sourceBitrate: Int
    ) -> Bool {
        guard !codecChanged, let targetBitrate = targetBitrate else {
            return false
        }
        return targetBitrate < sourceBitrate
    }
}
