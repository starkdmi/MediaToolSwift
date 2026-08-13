import AVFoundation
import CoreMedia

/// Calculates video bitrate based on various strategies
/// Calculates output bitrate and file-size estimates.
internal struct VideoBitrateCalculator {

    /// Result of bitrate calculation
    internal struct Result {
        /// Target bitrate in bits per second (nil = use encoder default)
        internal let targetBitrate: Int?

        /// Bitrate supplied to AVAssetWriter. This differs from
        /// `targetBitrate` when a request is capped to the source bitrate for
        /// parity with the legacy pipeline.
        internal let encoderBitrate: Int?

        /// Whether bitrate changed from source
        internal let bitrateChanged: Bool

        /// Whether estimated file size will be accurate
        internal let isEstimatedFileSizeAccurate: Bool

        /// Estimated output file size in kilobytes
        internal let estimatedFileSizeKB: Double
    }

    /// Calculate bitrate based on settings
    /// - Parameters:
    ///   - bitrateOption: The bitrate option from settings
    ///   - sourceBitrate: Source video bitrate in bits per second
    ///   - targetSize: Target video resolution
    ///   - codec: Output codec
    ///   - codecChanged: Whether codec differs from source
    ///   - isHDR: Whether video is HDR
    ///   - frameRate: Target frame rate
    ///   - duration: Video duration in seconds
    /// - Returns: Bitrate calculation result
    internal func calculate(
        bitrateOption: CompressionVideoBitrate,
        sourceBitrate: Float,
        targetSize: CGSize,
        sourceSize: CGSize,
        codec: AVVideoCodecType,
        codecChanged: Bool,
        isHDR: Bool,
        frameRate: Float,
        duration: Double
    ) throws -> Result {
        guard sourceBitrate.isFinite,
              sourceBitrate >= 0,
              Double(sourceBitrate) < Double(Int.max),
              duration.isFinite,
              duration >= 0 else {
            throw CompressionError.invalidVideoBitrate
        }
        let sourceBitrateValue = Int(sourceBitrate.rounded())

        // Check if codec supports bitrate setting
        let supportsBitrate = codec == .h264 || codec == .hevc || codec == .hevcWithAlpha

        guard supportsBitrate else {
            // ProRes and JPEG don't use bitrate
            return Result(
                targetBitrate: nil,
                encoderBitrate: nil,
                bitrateChanged: false,
                isEstimatedFileSizeAccurate: false,
                estimatedFileSizeKB: estimateFileSize(bitrate: Double(sourceBitrate), duration: duration)
            )
        }

        var targetBitrate: Int?
        var encoderBitrate: Int?
        var bitrateChanged = false
        let isEstimatedFileSizeAccurate: Bool

        /// Helper to set bitrate with source comparison
        /// Returns (bitrateToApply, shouldSetTargetBitrate)
        /// When capping to source, returns (sourceBitrate, false) to match original behavior
        /// where targetBitrate stays nil but compression settings use sourceBitrate
        func setBitrate(_ value: Int) -> (apply: Int, setTarget: Bool) {
            // For the same codec and resolution, use source bitrate as maximum
            if !codecChanged,
               targetSize.width <= sourceSize.width,
               targetSize.height <= sourceSize.height,
               sourceBitrateValue > 0 {
                if value >= sourceBitrateValue {
                    // Use source bitrate when higher value targeted
                    // Original behavior: apply sourceBitrate but leave targetBitrate as nil
                    return (sourceBitrateValue, false)
                } else {
                    // Require re-encoding to lower bitrate
                    bitrateChanged = true
                    return (value, true)
                }
            }
            return (value, true)
        }

        switch bitrateOption {
        case .value(let value):
            guard value > 0 else { throw CompressionError.invalidVideoBitrate }
            let result = setBitrate(value)
            encoderBitrate = result.apply
            if result.setTarget {
                targetBitrate = result.apply
            }
            // Note: When capped to source, result.apply is used for AVVideoAverageBitRateKey
            // but targetBitrate stays nil (matching original behavior)
            isEstimatedFileSizeAccurate = value >= 8_000_000

        case .dynamic(let handler):
            let value = handler(sourceBitrateValue)
            guard value > 0 else { throw CompressionError.invalidVideoBitrate }
            let result = setBitrate(value)
            encoderBitrate = result.apply
            if result.setTarget {
                targetBitrate = result.apply
            }
            isEstimatedFileSizeAccurate = value >= 8_000_000

        case .filesize(let filesize):
            guard filesize.isFinite, filesize > 0, duration > 0 else {
                throw CompressionError.invalidVideoBitrate
            }
            // Convert MB to bits and divide by duration
            var rate = filesize * Double(8_000_000) / duration

            // Limit based on source bitrate for H.264
            if codecChanged, codec == .h264 {
                if sourceBitrateValue > 0, rate >= Double(sourceBitrateValue) {
                    rate = Double(sourceBitrateValue)
                }
            }

            guard rate.isFinite, rate > 0, rate < Double(Int.max) else {
                throw CompressionError.invalidVideoBitrate
            }
            let result = setBitrate(Int(rate.rounded()))
            encoderBitrate = result.apply
            if result.setTarget {
                targetBitrate = result.apply
            }
            isEstimatedFileSizeAccurate = true

        case .auto:
            let bitrate = try calculateAutoBitrate(
                targetSize: targetSize,
                codec: codec,
                isHDR: isHDR,
                frameRate: frameRate
            )
            let result = setBitrate(bitrate)
            encoderBitrate = result.apply
            if result.setTarget {
                targetBitrate = result.apply
            }
            isEstimatedFileSizeAccurate = true

        case .source:
            guard sourceBitrateValue > 0 else {
                throw CompressionError.invalidVideoBitrate
            }
            targetBitrate = sourceBitrateValue
            encoderBitrate = sourceBitrateValue
            isEstimatedFileSizeAccurate = true

        case .encoder:
            targetBitrate = nil
            encoderBitrate = nil
            isEstimatedFileSizeAccurate = false
        }

        let rate = Double(encoderBitrate ?? sourceBitrateValue)
        let estimatedSize = estimateFileSize(bitrate: rate, duration: duration)

        return Result(
            targetBitrate: targetBitrate,
            encoderBitrate: encoderBitrate,
            bitrateChanged: bitrateChanged,
            isEstimatedFileSizeAccurate: isEstimatedFileSizeAccurate,
            estimatedFileSizeKB: estimatedSize
        )
    }

    /// Calculate automatic bitrate based on resolution and codec
    private func calculateAutoBitrate(
        targetSize: CGSize,
        codec: AVVideoCodecType,
        isHDR: Bool,
        frameRate: Float
    ) throws -> Int {
        var codecMultiplier: Float = 1.0
        if codec == .hevc || codec == .hevcWithAlpha {
            codecMultiplier = 0.5
        } else if codec == .h264 {
            codecMultiplier = 0.9
        }

        let bitsPerPixelMultiplier: Float = isHDR ? 1.25 : 1.0
        guard targetSize.width.isFinite,
              targetSize.height.isFinite,
              targetSize.width > 0,
              targetSize.height > 0,
              frameRate.isFinite,
              frameRate > 0 else {
            throw CompressionError.invalidVideoBitrate
        }
        let totalPixels = Double(targetSize.width * targetSize.height)
        let rate = totalPixels * Double(bitsPerPixelMultiplier * codecMultiplier * frameRate) / 8

        guard rate.isFinite, rate > 0, rate < Double(Int.max) else {
            throw CompressionError.invalidVideoBitrate
        }
        return Int(rate.rounded())
    }

    /// Estimate output file size in kilobytes
    private func estimateFileSize(bitrate: Double, duration: Double) -> Double {
        // bitrate (bits/sec) * duration (sec) / 8 (bits to bytes) / 1000 (bytes to KB)
        return bitrate * (duration / 60) * 0.0075
    }
}
