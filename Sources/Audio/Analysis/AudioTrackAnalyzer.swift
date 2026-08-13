import AVFoundation
import AudioToolbox

/// Analyzes an audio track to extract its properties
/// Shared by the audio-only and video conversion configuration paths.
internal struct AudioTrackAnalyzer {

    /// Result of audio track analysis
    internal struct Analysis {
        /// The audio track's format description
        internal let formatDescription: CMFormatDescription

        /// Source audio format ID
        internal let formatId: AudioFormatID

        /// Source audio codec
        internal let codec: CompressionAudioCodec

        /// Sample rate in Hz
        internal let sampleRate: Int

        /// Number of channels
        internal let channelsPerFrame: Int

        /// Bits per channel
        internal let bitsPerChannel: Int

        /// Whether audio is floating point
        internal let isFloat: Bool

        /// Whether audio is big endian
        internal let isBigEndian: Bool

        /// Estimated bitrate in bits per second
        internal let estimatedBitrate: Int
    }

    /// Analyze an audio track
    /// - Parameter track: The audio track to analyze
    /// - Returns: Analysis result with all track properties
    internal func analyze(track: AVAssetTrack) async throws -> Analysis {
        guard let formatDescription = await track.getFormatDescriptions().first else {
            throw CompressionError.failedToReadAudio
        }
        let formatId = CMFormatDescriptionGetMediaSubType(formatDescription)
        let codec = CompressionAudioCodec(formatId: formatId) ?? .default

        let basicDescription = formatDescription.audioBasicDescription

        let rawSampleRate = basicDescription?.mSampleRate ?? 44100
        let rawChannelsPerFrame = basicDescription?.mChannelsPerFrame ?? 2
        guard rawSampleRate.isFinite,
              rawSampleRate > 0,
              rawSampleRate < Double(Int.max),
              rawChannelsPerFrame > 0 else {
            throw CompressionError.failedToReadAudio
        }
        let sampleRate = Int(rawSampleRate)
        let channelsPerFrame = Int(rawChannelsPerFrame)

        var bitsPerChannel = Int(basicDescription?.mBitsPerChannel ?? 0)
        var isFloat = false
        var isBigEndian = false

        if let formatFlags = basicDescription?.mFormatFlags {
            isFloat = formatFlags & kAudioFormatFlagIsFloat != 0
            isBigEndian = formatFlags & kAudioFormatFlagIsBigEndian != 0
        }

        // Floating-point LPCM must be 32-bit
        if isFloat, bitsPerChannel != 32 {
            bitsPerChannel = 32
        }

        let rawEstimatedBitrate = await track.getEstimatedDataRate()
        guard rawEstimatedBitrate.isFinite,
              rawEstimatedBitrate >= 0,
              Double(rawEstimatedBitrate) < Double(Int.max) else {
            throw CompressionError.failedToReadAudio
        }
        let estimatedBitrate = Int(rawEstimatedBitrate.rounded())

        return Analysis(
            formatDescription: formatDescription,
            formatId: formatId,
            codec: codec,
            sampleRate: sampleRate,
            channelsPerFrame: channelsPerFrame,
            bitsPerChannel: bitsPerChannel,
            isFloat: isFloat,
            isBigEndian: isBigEndian,
            estimatedBitrate: estimatedBitrate
        )
    }

    /// Calculate bits per channel based on settings and source
    /// - Parameters:
    ///   - settings: Audio settings
    ///   - sourceAnalysis: Source track analysis
    /// - Returns: Calculated bits per channel
    internal func calculateBitsPerChannel(
        settings: CompressionAudioSettings,
        sourceAnalysis: Analysis
    ) -> Int {
        var bitsPerChannel = sourceAnalysis.bitsPerChannel

        if bitsPerChannel == 0 {
            // Calculate bits per channel based on bitrate, channels amount and audio quality
            let bitrate: Int
            if case .value(let value) = settings.bitrate {
                bitrate = value
            } else {
                bitrate = 128_000
            }
            let quality = (settings.quality ?? .high).rawValue
            if quality != 0 {
                // Formula: bitrate / (8 * channels * quality)
                let doubleValue = Double(bitrate) / (8 * Double(sourceAnalysis.channelsPerFrame) * Double(quality))

                // Limit values in range 0-31
                let intValue = Int(doubleValue + 0.5) & 0x1F

                // Find closest divisible by 8 value
                let remainder = intValue % 8
                bitsPerChannel = remainder == 0 ? intValue : intValue + (8 - remainder)

                // Bit depth can only be one of: 8, 16, 24, 32
                if ![8, 16, 24, 32].contains(bitsPerChannel) {
                    bitsPerChannel = 16
                }
            } else {
                // Minimal quality
                bitsPerChannel = 8
            }
        }

        return bitsPerChannel
    }
}

// MARK: - CMFormatDescription Audio Extension

private extension CMFormatDescription {
    /// Get audio stream basic description
    /// Using a private method name to avoid conflicts with system-provided properties
    var audioBasicDescription: AudioStreamBasicDescription? {
        return CMAudioFormatDescriptionGetStreamBasicDescription(self)?.pointee
    }
}
