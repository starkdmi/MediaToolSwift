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
        return try? self.seekToEnd()
    }
}
