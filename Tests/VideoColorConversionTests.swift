import AVFoundation
import CoreImage
import XCTest
@testable import MediaToolSwift

#if !os(visionOS)
final class VideoColorConversionTests: XCTestCase {
    func testDCIP3WriterSetupBeforeEncoding() async throws {
        let asset = AVURLAsset(url: try fixture("dci-p3"))
        do {
            let configured = try await VideoTool.initializeVideo(asset: asset,
                videoSettings: .init(codec: .hevc, profile: .hevcMain))
            XCTAssertNotNil(configured.videoInput)
        } catch {
            XCTFail("Writer setup failed: \(error.localizedDescription)")
        }
    }

    func testDCIP3SDRConversion() async throws {
        try await checkConversion("dci-p3", hdrTransfer: nil)
        #if !os(macOS)
        try await checkConversion("dci-p3", hdrTransfer: nil,
            processor: .imageComposition { image, _, _ in image })
        #endif
    }

    func testDCIP3HLGConversion() async throws {
        try await checkConversion("dci-p3-hlg", hdrTransfer: AVVideoTransferFunction_ITU_R_2100_HLG)
    }

    func testDCIP3PQConversion() async throws {
        try await checkConversion("dci-p3-pq", hdrTransfer: AVVideoTransferFunction_SMPTE_ST_2084_PQ)
    }

    func testDCIP3PortraitResizeWithImageProcessor() async throws {
        let source = try fixture("dci-p3-portrait")
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await convert(source, to: destination,
            settings: .init(codec: .hevc, size: .scale(CGSize(width: 48, height: 80)),
                profile: .hevcMain, edit: [.process(.image { image, _, _ in image })]))
        let info = try XCTUnwrap(result as? VideoInfo)
        XCTAssertEqual(info.resolution, CGSize(width: 48, height: 80))
        let image = try await firstFrame(AVURLAsset(url: destination))
        XCTAssertEqual(image.width, 48)
        XCTAssertEqual(image.height, 80)
    }

    func testDCIP3VideoPassthroughWhileDroppingAudio() async throws {
        let source = try fixture("dci-p3")
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        try await convert(source, to: destination, settings: .init(bitrate: .source), skipAudio: true)
        let original = AVURLAsset(url: source)
        let result = AVURLAsset(url: destination)
        let description = try await videoDescription(result)
        XCTAssertEqual(description.colorPrimaries, kCMFormatDescriptionColorPrimaries_DCI_P3 as String)
        let originalVideo = try await payload(original, type: .video)
        let resultVideo = try await payload(result, type: .video)
        XCTAssertEqual(resultVideo, originalVideo)
        let audioTracks = await result.getTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks?.count, 0)
    }

    private func checkConversion(_ name: String, hdrTransfer: String?, processor: VideoFrameProcessor? = nil) async throws {
        let source = try fixture(name)
        let destination = temporaryOutput()
        defer { try? FileManager.default.removeItem(at: destination) }
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .quickTimeMetadataDescription
        metadata.value = "color-conversion-regression" as NSString
        try await convert(
            source, to: destination,
            settings: .init(codec: .hevc,
                bitrate: hdrTransfer == nil ? .encoder : .value(300_000),
                quality: hdrTransfer == nil ? 1 : nil,
                profile: hdrTransfer == nil ? .hevcMain : .hevcMain10,
                edit: processor.map { [.process($0)] } ?? []),
            metadata: [metadata]
        )

        let original = AVURLAsset(url: source)
        let result = AVURLAsset(url: destination)
        let description = try await videoDescription(result)
        #if os(macOS)
        XCTAssertEqual(description.colorPrimaries, kCMFormatDescriptionColorPrimaries_DCI_P3 as String)
        #else
        XCTAssertEqual(description.colorPrimaries, hdrTransfer == nil
            ? AVVideoColorPrimaries_P3_D65 : AVVideoColorPrimaries_ITU_R_2020)
        #endif
        XCTAssertEqual(description.transferFunction, hdrTransfer ?? AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(description.isHDRVideo, hdrTransfer != nil)
        if hdrTransfer != nil {
            // Apple-created HEVC descriptions may omit BitsPerComponent.
            // hvcC records the actual encoded luma/chroma depths on every platform.
            let atoms = CMFormatDescriptionGetExtension(description,
                extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data]
            let hevc = try XCTUnwrap(atoms?["hvcC"])
            XCTAssertGreaterThan(hevc.count, 18)
            XCTAssertEqual(Int(hevc[17] & 7) + 8, 10)
            XCTAssertEqual(Int(hevc[18] & 7) + 8, 10)
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        XCTAssertEqual(dimensions.width, 160)
        XCTAssertEqual(dimensions.height, 96)
        let duration = await result.getDuration().seconds
        XCTAssertEqual(duration, 1, accuracy: 0.05)
        let originalAudio = try await payload(original, type: .audio)
        let resultAudio = try await payload(result, type: .audio)
        XCTAssertEqual(resultAudio, originalAudio, "Audio must not be re-encoded")
        let resultMetadata = await result.getMetadata()
        let descriptionItem = try XCTUnwrap(resultMetadata.first { $0.identifier == .quickTimeMetadataDescription })
        let descriptionValue = await descriptionItem.getValue() as? String
        XCTAssertEqual(descriptionValue, "color-conversion-regression")
        if hdrTransfer == nil {
            try await checkSDRPixels(original, result)
        }
    }

    private func checkSDRPixels(_ original: AVAsset, _ result: AVAsset) async throws {
        let sourceImage = try await firstFrame(original)
        let resultImage = try await firstFrame(result)
        #if os(macOS)
        let retaggingSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_709))
        #else
        let retaggingSpace = try XCTUnwrap(resultImage.colorSpace)
        #endif
        let incorrectlyRetagged = try XCTUnwrap(sourceImage.copy(colorSpace: retaggingSpace))
        #if os(macOS)
        let referenceImage = sourceImage
        #else
        // Use Apple's independent basic compositor as the color reference.
        // CGImage color matching applies a different white-point adaptation.
        let composition = AVMutableVideoComposition(propertiesOf: original)
        composition.colorPrimaries = AVVideoColorPrimaries_P3_D65
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        let referenceImage = try await firstFrame(original, composition: composition)
        #endif
        let expected = try linearPixels(referenceImage)
        let actual = try linearPixels(resultImage)
        let retagged = try linearPixels(incorrectlyRetagged)
        XCTAssertEqual(actual.count, expected.count)
        func meanError(_ pixels: [Float]) -> Float {
            zip(pixels, expected).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(expected.count)
        }
        let conversionError = meanError(actual)
        let retaggingError = meanError(retagged)
        print("DCI-P3 linear-RGB mean error: export=\(conversionError), retag-only=\(retaggingError)")
        XCTAssertLessThan(conversionError, 0.035)
        XCTAssertLessThan(conversionError, retaggingError * 0.5,
            "Changing tags alone must not satisfy the pixel-color check")
    }

    private func firstFrame(_ asset: AVAsset, composition: AVVideoComposition? = nil) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if #available(macOS 13, iOS 16, tvOS 16, *) {
            return try await generator.image(at: .zero).image
        } else {
            return try generator.copyCGImage(at: .zero, actualTime: nil)
        }
    }

    private func linearPixels(_ image: CGImage) throws -> [Float] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        var rgba = [Float](repeating: 0, count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes {
            CIContext().render(CIImage(cgImage: image), toBitmap: $0.baseAddress!,
                rowBytes: image.width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                format: .RGBAf, colorSpace: colorSpace)
        }
        XCTAssertTrue(rgba.allSatisfy(\.isFinite))
        return rgba.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : min(max(value, 0), 1)
        }
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "mov", subdirectory: "ColorFixtures"))
    }

    private func temporaryOutput() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MediaToolColor-\(UUID()).mov")
    }

    @discardableResult
    private func convert(
        _ source: URL, to destination: URL,
        settings: CompressionVideoSettings,
        skipAudio: Bool = false,
        metadata: [AVMetadataItem] = []
    ) async throws -> MediaInfo {
        let terminal = expectation(description: "Conversion terminal state")
        let state = LockedValue<CompressionState?>(nil)
        _ = await VideoTool.convert(
            source: source, destination: destination,
            videoSettings: settings, skipAudio: skipAudio, customMetadata: metadata
        ) { value in
            switch value {
            case .completed, .failed, .cancelled:
                state.set(value)
                terminal.fulfill()
            case .started:
                break
            }
        }
        await fulfillment(of: [terminal], timeout: 30)
        switch state.read() {
        case .completed(let info): return info
        case .failed(let error):
            // The exception catcher's underlying NSException cannot be archived
            // by XCTest on iOS; preserve its reason in a serializable test error.
            throw NSError(domain: "VideoColorConversionTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        case .cancelled: XCTFail("Unexpected cancellation")
        case .started, .none: XCTFail("No terminal state")
        }
        throw NSError(domain: "VideoColorConversionTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "No completed conversion"])
    }

    private func videoDescription(_ asset: AVAsset) async throws -> CMFormatDescription {
        let maybeTrack = await asset.getFirstTrack(withMediaType: .video)
        let track = try XCTUnwrap(maybeTrack)
        let descriptions = await track.getFormatDescriptions()
        return try XCTUnwrap(descriptions.first)
    }

    private func payload(_ asset: AVAsset, type: AVMediaType) async throws -> Data {
        let maybeTrack = await asset.getFirstTrack(withMediaType: type)
        let track = try XCTUnwrap(maybeTrack)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var payload = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            payload.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertFalse(payload.isEmpty)
        return payload
    }
}
#endif
