import Foundation
import CoreMedia
import QuartzCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Video operations
public enum VideoOperation: Equatable, Hashable {
    /// Cutting
    case cut(from: Double = 0.0, to: Double = .infinity)

    /// Cropping
    /// Not allowed when `size` of `CompressionVideoSettings` is set
    /// May not reduce the video size, it adjusts the rendering area without decoding/encoding each frame as image and modifying it
    /// May be used to increase video size - scale down video to square/rectangle with black background
    case crop(Crop)

    /// Rotation
    case rotate(Rotate)

    /// Flip upside down
    case flip

    /// Right to left mirror effect
    case mirror

    /// Overlay
    case overlay([any Overlay])

    /// Transform value
    var transform: CGAffineTransform? {
        switch self {
        case .rotate(let value):
            return CGAffineTransform(rotationAngle: value.radians)
        case .flip:
            return CGAffineTransform(scaleX: 1.0, y: -1.0)
        case .mirror:
            return CGAffineTransform(scaleX: -1.0, y: 1.0)
        default:
            return nil
        }
    }

    /// Hashable conformance
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .cut(from: from, to: to):
            hasher.combine("cut")
            hasher.combine(from)
            hasher.combine(to)
        case .crop(let value):
            hasher.combine("crop")
            hasher.combine(value.cropSize.width)
            hasher.combine(value.cropSize.height)
        case .rotate(let value):
            hasher.combine("rotate")
            hasher.combine(value.radians)
        case .flip:
            hasher.combine("flip")
        case .mirror:
            hasher.combine("mirror")
        case .overlay(let items):
            hasher.combine("overlay")
            hasher.combine(items.count)
        }
    }

    /// Equatable conformance
    public static func == (lhs: VideoOperation, rhs: VideoOperation) -> Bool {
        switch (lhs, rhs) {
        case (let .cut(lhsFrom, lhsTo), let .cut(rhsFrom, rhsTo)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo
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
}

/// Rotation enumeration
public enum Rotate: Equatable {
    /// Rotate in a rightward direction
    case clockwise

    /// Rotate in a leftward direction
    case counterclockwise

    /// Custom rotation angle in radians, most likely will be displayed as nearest 90' value
    case angle(Double)

    /// Angle
    var radians: Double {
        switch self {
        case .clockwise:
            return .pi/2
        case .counterclockwise:
            return -.pi/2
        case .angle(let value):
            return value
        }
    }
}

/// Rotation enumeration
public struct Crop {
    private var size: CGSize?
    private var aligment: Alignment?
    private var rect: CGRect?
    private var origin: CGPoint?

    /// Initialize using size and alignment
    public init(size: CGSize, aligment: Alignment = .center) {
        self.size = size
        self.aligment = aligment
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
        if let aligment = self.aligment, let cropSize = self.size {
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
}

/// Overlay interface
public protocol Overlay: Equatable {
    /// Presentation start time, in seconds
    var from: Double { get }

    /// Presentation end time, in seconds, use `nil` for the end of video
    var to: Double? { get }

    /// Overlay opacity
    var opacity: Float { get }

    /// Build `CALayer`
    func makeLayer() -> CALayer
}

/// Extensions on `Overlay`
public extension Overlay {
    /// Set base properties and add present/dismiss animations to layer
    var layer: CALayer {
        let layer = self.makeLayer()
        layer.opacity = self.opacity
        // Presentation time range using opacity animation
        layer.setTimeRangeAnimation(from: from, to: to, opacity: self.opacity)
        return layer
    }
}

/// Image overlay
public struct ImageOverlay: Overlay {
    /// Presentation start time, in seconds
    public var from: Double

    /// Presentation end time, in seconds, use `nil` for the end of video
    public var to: Double?

    /// Overlay opacity
    public var opacity: Float

    /// Image
    public var cgImage: CGImage

    /// Image size
    public var size: CGSize

    /// Image position (starting point)
    public var position: CGPoint

    /// Public initializer
    public init(from: Double = .zero, to: Double? = nil, opacity: Float = 1.0, cgImage: CGImage, size: CGSize, position: CGPoint) {
        self.from = from
        self.to = to
        self.opacity = opacity
        self.cgImage = cgImage
        self.size = size
        self.position = position
    }

    /// Build function
    public func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: position, size: size)
        layer.contents = cgImage
        layer.contentsGravity = .center
        layer.contentsScale = 1.0
        return layer
    }
}

/// Text overlay
public struct TextOverlay: Overlay {
    #if os(macOS)
    public typealias Font = NSFont
    #else
    public typealias Font = UIFont
    #endif

    /// Presentation start time, in seconds
    public var from: Double

    /// Presentation end time, in seconds, use `nil` for the end of video
    public var to: Double?

    /// Overlay opacity
    public var opacity: Float

    /// Text
    public var text: String

    /// Text position (starting point)
    public var position: CGPoint

    /// Text font
    public var font: Font

    /// Text color
    public var foregroundColor: CGColor

    /// Background color
    public var backgroundColor: CGColor

    /// Public initializer
    public init(from: Double = .zero, to: Double? = nil, opacity: Float = 1.0, text: String, position: CGPoint, font: Font, foregroundColor: CGColor, backgroundColor: CGColor = .clear) {
        self.from = from
        self.to = to
        self.opacity = opacity
        self.text = text
        self.position = position
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    /// Build function
    public func makeLayer() -> CALayer {
        let layer = CATextLayer()
        layer.string = self.text
        layer.alignmentMode = .center
        layer.font = self.font
        layer.foregroundColor = self.foregroundColor
        layer.backgroundColor = self.backgroundColor
        layer.frame = CGRect(origin: self.position, size: layer.preferredFrameSize())
        layer.displayIfNeeded()
        return layer
    }
}

/// Custom `CALayer` overlay
public struct CustomOverlay: Overlay {
    /// Presentation start time, in seconds
    public var from: Double

    /// Presentation end time, in seconds, use `nil` for the end of video
    public var to: Double?

    /// Overlay opacity
    public var opacity: Float

    /// Custom layer
    public var layer: CALayer

    /// Public initializer
    public init(from: Double = .zero, to: Double? = nil, opacity: Float = 1.0, layer: CALayer) {
        self.from = from
        self.to = to
        self.opacity = opacity
        self.layer = layer
    }

    /// Build function
    public func makeLayer() -> CALayer {
        return layer
    }
}
