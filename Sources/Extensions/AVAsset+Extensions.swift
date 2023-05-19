import AVFoundation

/// Public extension for AVAsset
public extension AVAsset {
    /// Load tracks using newer API if possible and the deprecated one otherwise
    /// - Parameter type: Media type
    /// - Returns: List of tracks or nil
    func getTracks(withMediaType type: AVMediaType) async -> [AVAssetTrack]? {
        if #available(iOS 15, OSX 12, *) {
            return try? await self.loadTracks(withMediaType: type)
        } else {
            // fallback to deprecated sync API
            return self.tracks(withMediaType: type)
        }
    }

    /// Get first track shortcut
    /// - Parameter type: Media type
    /// - Returns: First track of `type` or nil
    func getFirstTrack(withMediaType type: AVMediaType) async -> AVAssetTrack? {
        return await self.getTracks(withMediaType: type)?.first
    }

    /// Retvieve asset metadata such as iTunes, QuickTime, ID3, ISO, atd.
    /// https://developer.apple.com/documentation/avfoundation/media_assets/retrieving_media_metadata
    /// - Returns: List of metadata items
    func getMetadata() async -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []
        if #available(iOS 15, macOS 12, *) {
            if let formats = try? await self.load(.availableMetadataFormats) {
                for format in formats {
                    if let data = try? await self.loadMetadata(for: format) {
                        metadata.append(contentsOf: data)
                    }
                }
            }
        } else {
            // Fallback on earlier versions
            for format in self.availableMetadataFormats {
                let data = self.metadata(forFormat: format)
                metadata.append(contentsOf: data)
            }
        }
        return metadata
    }
}
