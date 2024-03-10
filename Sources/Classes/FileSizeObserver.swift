//
//  FileSizeObserver.swift
//  
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import Foundation

/// File size changes observer
public class FileSizeObserver {
    /// Target file path
    let url: URL

    /// The dispatch queue used by `DispatchSource`
    let queue: DispatchQueue?

    /// File size changes callback
    let onChange: (_ fileSize: UInt64) -> Void

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?

    /// Initialzie and activate file size change observer
    public init(url: URL, queue: DispatchQueue? = nil, onChange: @escaping (UInt64) -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange

        // Create file descriptor
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            self.fileHandle = fileHandle

            // Init file update/extend observer
            self.source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileHandle.fileDescriptor,
                eventMask: .extend,
                queue: queue
            )

            // Get file size on file change/update events
            self.source?.setEventHandler { [weak self] in
                guard let self = self else { return }

                if self.source?.data == .extend {
                    if let fileSize = fileHandle.seekToFileEnd() {
                        // Get file size using seeking the reading pointer (unique per file handle)
                        self.onChange(fileSize)
                    } else if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                        let fileSize = attributes[FileAttributeKey.size] as? UInt64 {
                        // Get file size using File Manager API
                        self.onChange(fileSize)
                    }
                }
            }

            // Prepare for cleanup call
            self.source?.setCancelHandler {
                try? fileHandle.close()
            }

            // Run observer
            self.source?.activate() // .resume()
        }
    }

    /// Deinitialize
    deinit {
        self.finish()
    }

    /// Close file handle and complete the observer
    public func finish() {
        self.source?.cancel()
    }
}
