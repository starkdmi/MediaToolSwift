import AVFoundation

/// Extensions on `AVAssetTrack`
internal extension AVAssetTrack {
    /// Load format descriptions using the modern property API.
    func getFormatDescriptions() async -> [CMFormatDescription] {
        return (try? await load(.formatDescriptions)) ?? []
    }

    /// Load estimated data rate using the modern property API.
    func getEstimatedDataRate() async -> Float {
        return (try? await load(.estimatedDataRate)) ?? 0
    }

    /// Load nominal frame rate using the modern property API.
    func getNominalFrameRate() async -> Float {
        return (try? await load(.nominalFrameRate)) ?? 0
    }

    /// Load natural size using the modern property API.
    func getNaturalSize() async -> CGSize {
        return (try? await load(.naturalSize)) ?? .zero
    }

    /// Load preferred transform using the modern property API.
    func getPreferredTransform() async -> CGAffineTransform {
        return (try? await load(.preferredTransform)) ?? .identity
    }

    /// Apply fixes to the rotations or flips.
    /// Fix transform translation issue from https://stackoverflow.com/a/64161545/4833705
    func getFixedPreferredTransform() async -> CGAffineTransform {
        var transform = await getPreferredTransform()
        let naturalSize = await getNaturalSize()
        switch(transform.a, transform.b, transform.c, transform.d) {
        case (1, 0, 0, 1):
            transform.tx = 0
            transform.ty = 0
        case (1, 0, 0, -1):
            transform.tx = 0
            transform.ty = naturalSize.height
        case (-1, 0, 0, 1):
            transform.tx = naturalSize.width
            transform.ty = 0
        case (-1, 0, 0, -1):
            transform.tx = naturalSize.width
            transform.ty = naturalSize.height
        case (0, -1, 1, 0):
            transform.tx = 0
            transform.ty = naturalSize.width
        case (0, 1, -1, 0):
            transform.tx = naturalSize.height
            transform.ty = 0
        case (0, 1, 1, 0):
            transform.tx = 0
            transform.ty = 0
        case (0, -1, -1, 0):
            transform.tx = naturalSize.height
            transform.ty = naturalSize.width
        default:
            break
        }
        return transform
    }

    /// Transform orientation
    /// Quarter turns, including reflected ones (transposes), swap the displayed dimensions
    func getOrientation() async -> VideoOrientation {
        let transform = await getPreferredTransform()
        if transform.a == 0 && transform.d == 0 && abs(transform.b) == 1.0 && abs(transform.c) == 1.0 {
            return .portrait
        } else {
            return .landscape
        }
    }

    /// Video size applying transform
    func getNaturalSizeWithOrientation() async -> CGSize {
        let naturalSize = await getNaturalSize()
        let orientation = await getOrientation()
        return naturalSize.oriented(orientation)
    }

    /// Video time scale
    func getVideoTimeScale() async -> CMTimeScale {
        guard self.mediaType == .video else { return .zero }

        let scale = try? await self.load(.naturalTimeScale)
        return scale ?? .zero
    }

    /// Estimated data rate rounded to integer
    func getEstimatedDataRateInt() async -> Int {
        let rate = await getEstimatedDataRate()
        guard rate.isFinite,
              rate >= 0,
              Double(rate) < Double(Int.max) else {
            return 0
        }
        return Int(rate.rounded())
    }
}
