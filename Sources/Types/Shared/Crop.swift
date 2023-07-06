import Foundation

/// Cropping interface
public struct Crop: Equatable, Hashable {
    private var size: CGSize?
    private var alignment: Alignment?
    private var rect: CGRect?
    private var origin: CGPoint?

    /// Initialize using size and alignment
    public init(size: CGSize, aligment: Alignment = .center) {
        self.size = size
        self.alignment = aligment
    }

    /// Initialize using rectangle, origin at (0, 0) is a left bottom corner
    public init(rect: CGRect) {
        self.rect = rect
    }

    /// Initialize using starting point and size, point at (0, 0) is a left bottom corner
    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    /// Cropping area size
    public var cropSize: CGSize {
        return self.size ?? self.rect?.size ?? .zero
    }

    /// Calculate cropping rectangle
    public func makeCroppingRectangle(in size: CGSize) -> CGRect {
        if let aligment = self.alignment, let cropSize = self.size {
            let cropOrigin: CGPoint
            switch aligment {
            case .center:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: (size.height - cropSize.height) / 2)
            case .topLeading:
                cropOrigin = CGPoint(x: 0, y: 0)
            case .top:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: 0)
            case .topTrailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: 0)
            case .leading:
                cropOrigin = CGPoint(x: 0, y: (size.height - cropSize.height) / 2)
            case .trailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: (size.height - cropSize.height) / 2)
            case .bottom:
                cropOrigin = CGPoint(x: (size.width - cropSize.width) / 2, y: size.height - cropSize.height)
            case .bottomLeading:
                cropOrigin = CGPoint(x: 0, y: size.height - cropSize.height)
            case .bottomTrailing:
                cropOrigin = CGPoint(x: size.width - cropSize.width, y: size.height - cropSize.height)
            }
            return CGRect(origin: cropOrigin, size: cropSize)
        } else if let rect = self.rect {
            return rect
        } else if let origin = self.origin, let size = self.size {
            return CGRect(origin: origin, size: size)
        }

        return .zero
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine("crop")
        hasher.combine(cropSize.width)
        hasher.combine(cropSize.height)
    }

    /// Equatable conformance
    public static func == (lhs: Crop, rhs: Crop) -> Bool {
        return lhs.size == rhs.size && lhs.alignment == rhs.alignment && lhs.rect == rhs.rect && lhs.origin == rhs.origin
    }
}
