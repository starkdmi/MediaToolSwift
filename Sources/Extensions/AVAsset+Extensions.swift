import AVFoundation

/// Extensions on `AVAsset`
internal extension AVAsset {
    /// Load duration using the modern property API.
    func getDuration() async -> CMTime {
        return (try? await load(.duration)) ?? .zero
    }

    /// Load tracks of a given media type
    /// - Parameter type: Media type
    /// - Returns: List of tracks or nil
    func getTracks(withMediaType type: AVMediaType) async -> [AVAssetTrack]? {
        return try? await self.loadTracks(withMediaType: type)
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
        if let formats = try? await self.load(.availableMetadataFormats) {
            for format in formats {
                if let data = try? await self.loadMetadata(for: format) {
                    metadata.append(contentsOf: data)
                }
            }
        }
        return metadata
    }
}

internal extension AVMetadataItem {
    /// Load metadata values without using the deprecated synchronous accessors.
    func getValue() async -> (any NSCopying & NSObjectProtocol)? {
        return try? await load(.value)
    }
}
