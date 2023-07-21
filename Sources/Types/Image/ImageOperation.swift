import Foundation
import CoreImage

/// Image operations
public enum ImageOperation: Equatable, Hashable, Comparable {
    /// Cropping
    case crop(Crop)

    /// Rotation
    case rotate(Rotate)

    /// Flip upside down
    case flip

    /// Right to left mirror effect
    case mirror

    /// Custom image processing function, appplied after all the other image operations
    case imageProcessing((_ image: CIImage) -> CIImage)

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .crop(let value):
            hasher.combine(value)
        case .rotate(let value):
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
        case (.crop(let lhsCrop), .crop(let rhsCrop)):
            return lhsCrop == rhsCrop
        case (.rotate(let lhsRotation), .rotate(let rhsRotation)):
            return lhsRotation == rhsRotation
        case (.flip, .flip):
            return true
        case (.mirror, .mirror):
            return true
        default:
            return false
        }
    }

    /// Operation priority
    private var priority: Int {
        switch self {
        case .crop(_):
            return 1
        case .rotate(_):
            return 2
        case .flip:
            return 3
        case .mirror:
            return 4
        case .imageProcessing(_):
            // Should be executed after all the operations
            return 100
        }
    }

    /// Comparable conformance
    public static func < (lhs: ImageOperation, rhs: ImageOperation) -> Bool {
        return lhs.priority < rhs.priority
    }

    /// Apply multiple image operations on `CGImage`
    static func apply(_ image: CGImage, operations: Set<ImageOperation>, resize: CGSize? = nil) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)

        // Convert to CIImage
        let context = CIContext()
        var ciImage = CIImage(cgImage: image, options: [.applyOrientationProperty: true])

        // Resize
        if let resize = resize {
            let scaleX = resize.width / size.width
            let scaleY = resize.height / size.height
            ciImage = ciImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        // Apply operations in sorted order
        for operation in operations.sorted() {
            switch operation {
            case .crop(let options):
                let rect = options.makeCroppingRectangle(in: size)
                ciImage = ciImage.cropped(to: rect)
                    .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
            case .rotate(let value):
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(rotationAngle: value.radians))
            case .flip:
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(scaleX: 1.0, y: -1.0))
            case .mirror:
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(scaleX: -1.0, y: 1.0))
            case .imageProcessing(let function):
                ciImage = function(ciImage)
            }
        }

        // Create a CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return cgImage
    }
}
