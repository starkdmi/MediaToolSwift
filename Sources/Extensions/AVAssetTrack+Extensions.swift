import AVFoundation

/// Extensions on `AVAssetTrack`
internal extension AVAssetTrack {
    /// Apply fixes to the rotations or flips
    /// Fix transform translation issue from https://stackoverflow.com/a/64161545/4833705
    var fixedPreferredTransform: CGAffineTransform {
        var transform = preferredTransform
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
    var orientation: VideoOrientation {
        let transform = preferredTransform
        if (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) ||
            (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0) {
            return .portrait
        } else {
            return .landscape
        }
    }

    /// Video size applying transform
    var naturalSizeWithOrientation: CGSize {
        return naturalSize.oriented(orientation)
    }

    /// Video time scale
    func getVideoTimeScale() async -> CMTimeScale {
        guard self.mediaType == .video else { return .zero }

        if #available(macOS 12, iOS 15, tvOS 15, *) {
            let scale = try? await self.load(.naturalTimeScale)
            return scale ?? .zero
        } else {
            return self.naturalTimeScale
        }
    }

    /// Estimated data rate rounded to integer
    var estimatedDataRateInt: Int {
        Int(self.estimatedDataRate.rounded())
    }
}
