import Foundation
import CoreImage

/// Image rotation fill options
public enum RotationFill {
    /// Crop and zoom to fill rectangular shape while preserving aspect ratio
    case crop

    /// Blur extended area, only odd numbers allowed for `kernel`
    /// Warning: not allowed for images with alpha channel and `CGImage`
    case blur(kernel: UInt32)

    /// Fill extended area with color, use transparent (0, 0, 0, 0) for clear background
    /// Warning: Black color may appear instead of transparent for some formats (for example non-HEIF images without alpha channel)
    case color(alpha: UInt8, red: UInt8, green: UInt8, blue: UInt8)

    // Scale blur kernel
    internal func scaled(by scale: CGFloat) -> RotationFill {
        guard scale != 1.0 else { return self }
        switch self {
        case .blur(let kernel):
            return .blur(kernel: UInt32(CGFloat(kernel) * scale))
        case .crop, .color:
            return self
        }
    }
}

/// Image processor type
/// Only one image passed in based on `preferredFramework` and internal framework support (`CIImage` doesn't support animations)
/// Return image of the same type to be written - when `CGImage` is not `nil`, modify and return `CGImage` while passing `nil` for `CIImage`
/// Index used as a frame number (starts with zero), `0` for static images
public typealias ImageProcessor = (_ ciImage: CIImage?, _ cgImage: CGImage?, _ orientation: CGImagePropertyOrientation?, _ index: Int) -> (ciImage: CIImage?, cgImage: CGImage?)

/// Image operations
public enum ImageOperation: Equatable, Hashable, Comparable {
    /// Rotation
    /// Angle precision may wary between devices and methods (`vImage`, `CIImage`)
    /// The resulting images may have different dimension depending on destination format and device
    case rotate(_: Rotate, fill: RotationFill = .crop)

    /// Reflect vertically
    case flip

    /// Reflect horizontally (right to left mirror effect)
    case mirror

    /// Custom image processing function, appplied after all the other image operations
    case imageProcessing(ImageProcessor)

    /// Operation priority
    private var priority: Int {
        switch self {
        case .rotate(_, _):
            return 1
        case .flip:
            return 2
        case .mirror:
            return 3
        case .imageProcessing(_):
            // Should be executed after all the operations
            return 100
        }
    }

    /// Determine if `ImageOperation` is rotation and the angle isn't multiply of 90 degree
    internal var isRotationByCustomAngle: Bool {
        if case .rotate(let rotation, _) = self {
            // Small threshold is used for small difference between types
            return abs(rotation.radians).truncatingRemainder(dividingBy: .pi/2) > 1e-6
        }
        return false
    }

    /// Whether numeric operation parameters can safely be handed to Core
    /// Graphics, Core Image, and vImage.
    internal var hasValidGeometry: Bool {
        if case .rotate(let rotation, _) = self {
            return rotation.radians.isFinite
        }
        return true
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .rotate(let value, _):
            hasher.combine(value)
        case .flip:
            hasher.combine("flip")
        case .mirror:
            hasher.combine("mirror")
        case .imageProcessing(_):
             hasher.combine("ImageProcessing")
        }
    }

    /// Equatable conformance
    public static func == (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        switch (lhs, rhs) {
        case (.rotate(let lhsRotation, _), .rotate(let rhsRotation, _)):
            return lhsRotation == rhsRotation
        case (.flip, .flip):
            return true
        case (.mirror, .mirror):
            return true
        case (.imageProcessing, .imageProcessing):
            return true
        default:
            return false
        }
    }

    /// Comparable conformance
    public static func < (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        return lhs.priority < rhs.priority
    }
}

internal extension Set where Element == ImageOperation {
    /// Whether every operation has finite geometry.
    var hasValidGeometry: Bool {
        allSatisfy(\.hasValidGeometry)
    }

    /// Determine if any `ImageOperation` is rotation and the angle isn't multiply of 90 degree
    var containsRotationByCustomAngle: Bool {
        return self.contains(where: { $0.isRotationByCustomAngle })
    }

    /// Scale operations for gain map processing
    func scaled(by scale: CGFloat) -> Set<ImageOperation> {
        guard scale != 1.0 else { return self }
        return Set(self.compactMap { operation in
            switch operation {
            case let .rotate(angle, fill):
                return .rotate(angle, fill: fill.scaled(by: scale))
            case .flip, .mirror:
                return operation // no scaling needed
            case .imageProcessing:
                return nil // drop custom processor when scaling
                /*// Wrap processor to scale before and after
                return .imageProcessing({ ciImage, cgImage, orientation, index in
                    let scaleFactor = 1.0 / scale

                    // Scale whichever input is provided
                    if let ciImage = ciImage {
                        // `CIImage` path
                        let scaled = ciImage.resizing(to: CGSize(
                            width: ciImage.extent.width * scaleFactor,
                            height: ciImage.extent.height * scaleFactor
                        ))
                        let processed = processor(scaled, nil, orientation, index)

                        // Scale back result
                        if let processedCIImage = processed.ciImage {
                            let rescaled = processedCIImage.resizing(to: CGSize(
                                width: processedCIImage.extent.width * scale,
                                height: processedCIImage.extent.height * scale
                            ))
                            return (ciImage: rescaled, cgImage: nil)
                        }
                    } else if let cgImage = cgImage {
                        // `CGImage` path
                        let scaled = cgImage.resizing(to: CGSize(
                            width: CGFloat(cgImage.width) * scaleFactor,
                            height: CGFloat(cgImage.height) * scaleFactor
                        ))
                        let processed = processor(nil, scaled, orientation, index)

                        // Scale back result
                        if let processedCGImage = processed.cgImage {
                            let rescaled = processedCGImage.resizing(to: CGSize(
                                width: CGFloat(processedCGImage.width) * scale,
                                height: CGFloat(processedCGImage.height) * scale
                            ))
                            return (ciImage: nil, cgImage: rescaled)
                        }
                    }

                    return (ciImage: nil, cgImage: nil)
                })*/
            }
        })
    }
}
