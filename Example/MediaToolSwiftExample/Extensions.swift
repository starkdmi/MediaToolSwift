//
//  Extensions.swift
//  MediaToolSwiftExample
//
//  Created by Dmitry Starkov on 12/05/2023.
//

import Foundation
import MediaToolSwift
import CoreGraphics

extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width > height)
        hasher.combine(width)
        hasher.combine(height)
    }
}

extension CompressionVideoBitrate: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .auto: hasher.combine(-1)
        case .encoder: hasher.combine(-2)
        case .value(let value): hasher.combine(value)
        }
    }
}

extension URL {
    public var fileSizeInMB: Double? {
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: self.path)[FileAttributeKey.size] else {
            return nil
        }

        let bytes = Float(fileSize as! UInt64)
        return Double(bytes / 1024.0 / 1024.0)
    }
}
