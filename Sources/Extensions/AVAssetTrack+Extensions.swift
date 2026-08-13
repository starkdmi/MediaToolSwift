import AVFoundation

/// Extensions on `AVAssetTrack`
internal extension AVAssetTrack {
    /// Load format descriptions using the modern property API where available.
    func getFormatDescriptions() async -> [CMFormatDescription] {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return (try? await load(.formatDescriptions)) ?? []
        } else {
            #if os(visionOS)
            return (try? await load(.formatDescriptions)) ?? []
            #else
            return formatDescriptions as! [CMFormatDescription] // swiftlint:disable:this force_cast
            #endif
        }
    }

    /// Load estimated data rate using the modern property API where available.
    func getEstimatedDataRate() async -> Float {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return (try? await load(.estimatedDataRate)) ?? 0
        } else {
            #if os(visionOS)
            return (try? await load(.estimatedDataRate)) ?? 0
            #else
            return estimatedDataRate
            #endif
        }
    }

    /// Load nominal frame rate using the modern property API where available.
    func getNominalFrameRate() async -> Float {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return (try? await load(.nominalFrameRate)) ?? 0
        } else {
            #if os(visionOS)
            return (try? await load(.nominalFrameRate)) ?? 0
            #else
            return nominalFrameRate
            #endif
        }
    }

    /// Load natural size using the modern property API where available.
    func getNaturalSize() async -> CGSize {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return (try? await load(.naturalSize)) ?? .zero
        } else {
            #if os(visionOS)
            return (try? await load(.naturalSize)) ?? .zero
            #else
            return naturalSize
            #endif
        }
    }

    /// Load preferred transform using the modern property API where available.
    func getPreferredTransform() async -> CGAffineTransform {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return (try? await load(.preferredTransform)) ?? .identity
        } else {
            #if os(visionOS)
            return (try? await load(.preferredTransform)) ?? .identity
            #else
            return preferredTransform
            #endif
        }
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
    func getOrientation() async -> VideoOrientation {
        let transform = await getPreferredTransform()
        if (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) ||
            (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0) {
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

        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            let scale = try? await self.load(.naturalTimeScale)
            return scale ?? .zero
        } else {
            #if os(visionOS)
            return (try? await self.load(.naturalTimeScale)) ?? .zero
            #else
            return self.naturalTimeScale
            #endif
        }
    }

    /// Estimated data rate rounded to integer
    func getEstimatedDataRateInt() async -> Int {
        Int((await getEstimatedDataRate()).rounded())
    }
}
