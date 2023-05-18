import AVFoundation

/// Public extension for [AVAssetTrack]
public extension AVAssetTrack {
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
}
