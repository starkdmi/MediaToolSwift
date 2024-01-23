import CoreMedia
import CoreImage
import Accelerate

/// Video frame processors
public enum VideoFrameProcessor: Equatable, Hashable {
    /// CIImage processing function using  `CVPixelBuffer` and  `AVAssetWriterInputPixelBufferAdaptor`
    /// By returning `nil` the frame will be dropped
    case image((_ image: CIImage, _ context: CIContext, _ time: Double) -> CIImage?)

    #if !os(visionOS)
    /// CIImage processing function using  `AVVideoComposition`
    case imageComposition((_ image: CIImage, _ context: CIContext, _ time: Double) -> CIImage)
    // case imageComposition(renderSize: CGSize? = nil, _ handler: (_ image: CIImage, _ context: CIContext, _ time: Double) -> CIImage)
    #endif

    /// CGImage processing function using  `CVPixelBuffer` and  `AVAssetWriterInputPixelBufferAdaptor`
    /// By returning `nil` the frame will be dropped
    case cgImage((_ image: CGImage, _ time: Double) -> CGImage?)

    /// vImage processing function
    /// By returning `nil` the frame will be dropped
    case vImage((_ image: vImage_Buffer, _ time: Double) -> vImage_Buffer?)

    /// Pixel buffer processing function
    /// Use provided `pool` to create a new `CVPixelBuffer`
    /// By returning `nil` the frame will be dropped
    case pixelBuffer((_ buffer: CVPixelBuffer, _ pool: CVPixelBufferPool, _ context: CIContext, _ time: Double) -> CVPixelBuffer?)

    /// Sample processing function
    /// By returning `nil` the frame will be dropped
    case sampleBuffer((_ buffer: CMSampleBuffer) -> CMSampleBuffer?)

    /// Indicator of cropping supported by processor
    internal var canCrop: Bool {
        switch self {
        case .image, .cgImage, .vImage:
            return true
        #if !os(visionOS)
        case .imageComposition:
            return false
        #endif
        case .pixelBuffer, .sampleBuffer:
            return false
        }
    }

    /// `AVAssetWriterInputPixelBufferAdaptor` requirement
    internal var requirePixelAdaptor: Bool {
        switch self {
        case .image, .cgImage, .vImage, .pixelBuffer:
            return true
        #if !os(visionOS)
        case .imageComposition:
            return false
        #endif
        case .sampleBuffer:
            return false
        }
    }

    /// `CIContext` requirement
    internal var requireCIContext: Bool {
        switch self {
        case .image, .pixelBuffer:
            return true
        #if !os(visionOS)
        case .imageComposition:
            return true
        #endif
        case .cgImage, .vImage, .sampleBuffer:
            return false
        }
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .image:
            hasher.combine("ciImageProcessor")
        #if !os(visionOS)
        case .imageComposition:
            hasher.combine("videoCompositionProcessor")
        #endif
        case .cgImage:
            hasher.combine("cgImageProcessor")
        case .vImage:
            hasher.combine("vImageProcessor")
        case .pixelBuffer:
            hasher.combine("pixelBufferProcessor")
        case .sampleBuffer:
            hasher.combine("sampleBufferProcessor")
        }
    }

    /// Equatable conformance
    public static func == (lhs: VideoFrameProcessor, rhs: VideoFrameProcessor) -> Bool {
        switch (lhs, rhs) {
        case (.image, .image):
            return true
        #if !os(visionOS)
        case (.imageComposition, .imageComposition):
            return true
        #endif
        case (.cgImage, .cgImage):
            return true
        case (.vImage, .vImage):
            return true
        case (.pixelBuffer, .pixelBuffer):
            return true
        case (.sampleBuffer, .sampleBuffer):
            return true
        default:
            return false
        }
    }
}
