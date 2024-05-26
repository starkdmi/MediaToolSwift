//
//  ImageObject.swift
//
//
//  Created by Dmitry Starkov on 25/05/2024.
//

import Foundation

/// Decoded Image
public struct Image {
    /// Image frames, single for static image
    public let frames: [ImageFrame]

    /// Image info
    public let info: ImageInfo

    /// Image format
    public let format: ImageFormat?

    /// Image size
    public let size: CGSize

    /// Image metadata
    public let primaryProperties: [CFString: Any]?

    /// Primary frame index
    public let primaryIndex: Int

    /// Alpha channel presence
    public let hasAlpha: Bool

    /// Image framework to use for editing
    public let processingMethod: ImageFramework
}
