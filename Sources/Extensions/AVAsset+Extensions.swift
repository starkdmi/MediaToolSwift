import AVFoundation

/// Extensions on `AVAsset`
internal extension AVAsset {
    /// Load tracks using newer API if possible and the deprecated one otherwise
    /// - Parameter type: Media type
    /// - Returns: List of tracks or nil
    func getTracks(withMediaType type: AVMediaType) async -> [AVAssetTrack]? {
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
            return try? await self.loadTracks(withMediaType: type)
        } else {
            // Fallback to deprecated sync API
            #if os(visionOS)
            // Not supported on visionOS, will never be reached
            return try? await self.loadTracks(withMediaType: type)
            #else
            return self.tracks(withMediaType: type)
            #endif
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
        if #available(macOS 12, iOS 15, tvOS 15, visionOS 1, *) {
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
                #if os(visionOS)
                let data = try? await self.loadMetadata(for: format)
                guard let data = data else { continue }
                #else
                let data = self.metadata(forFormat: format)
                #endif

                metadata.append(contentsOf: data)
            }
        }
        return metadata
    }
}
