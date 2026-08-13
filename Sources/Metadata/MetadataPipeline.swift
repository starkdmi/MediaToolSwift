@preconcurrency import AVFoundation
import Foundation

// MARK: - Metadata Initialization

extension VideoTool {

    /// Initializes timed-track and container metadata for a conversion.
    ///
    /// - Parameters:
    ///   - asset: The source asset
    ///   - skipSourceMetadata: Whether to skip reading source metadata
    ///   - customMetadata: Custom metadata items to include
    /// - Returns: Initialized MetadataVariables
    internal static func initializeMetadata(
        asset: AVAsset,
        skipSourceMetadata: Bool,
        customMetadata: [AVMetadataItem]
    ) async -> MetadataVariables {
        var variables = MetadataVariables()

        // Step 1: Analyze metadata track
        let trackAnalyzer = MetadataTrackAnalyzer()
        let analysis = await trackAnalyzer.analyze(asset: asset, skipSourceMetadata: skipSourceMetadata)

        // Step 2: Create I/O if metadata track exists
        var hasMetadata = false
        if analysis.hasTimedMetadataTrack,
           let metadataTrack = analysis.metadataTrack,
           let formatDescription = analysis.formatDescription {

            let ioFactory = MetadataIOFactory()
            let ioResult = ioFactory.createIO(
                metadataTrack: metadataTrack,
                formatDescription: formatDescription
            )

            if ioResult.isValid {
                variables.metadataOutput = ioResult.readerOutput
                variables.metadataInput = ioResult.writerInput
                hasMetadata = true
            }
        }

        // Step 3: Resolve final metadata (source + custom)
        let resolver = MetadataResolver()
        let finalMetadata = resolver.resolve(
            sourceMetadata: analysis.assetMetadata,
            customMetadata: customMetadata
        )

        variables.hasMetadata = hasMetadata
        variables.metadata = finalMetadata

        return variables
    }
}
