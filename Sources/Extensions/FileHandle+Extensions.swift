//
//  FileHandle+Extensions.swift
//
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import Foundation

/// Extensions on `FileHandle`
internal extension FileHandle {
    func seekToFileEnd() -> UInt64? {
        if #available(macOS 11, iOS 13.4, tvOS 13.4, *) {
            return try? self.seekToEnd()
        } else {
            return self.seekToEndOfFile()
        }
    }
}
