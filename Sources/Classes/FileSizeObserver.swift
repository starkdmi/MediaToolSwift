//
//  FileSizeObserver.swift
//  
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import Foundation

private final class FileSizeObserverState: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let onChange: (UInt64) -> Void
    private let fileHandle: FileHandle?
    private let source: DispatchSourceFileSystemObject?
    private var isFinished = false

    init(
        url: URL,
        queue: DispatchQueue?,
        onChange: @escaping (UInt64) -> Void
    ) {
        self.url = url
        self.onChange = onChange

        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            self.fileHandle = nil
            source = nil
            return
        }
        self.fileHandle = fileHandle

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileHandle.fileDescriptor,
            eventMask: .extend,
            queue: queue
        )
        self.source = source

        source.setEventHandler { [weak self] in
            self?.reportFileSize()
        }
        source.setCancelHandler {
            try? fileHandle.close()
        }
        source.activate()
    }

    deinit {
        finish()
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let source = source
        lock.unlock()

        source?.cancel()
    }

    private func reportFileSize() {
        let fileSize: UInt64?
        if let currentSize = fileHandle?.seekToFileEnd() {
            fileSize = currentSize
        } else if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let currentSize = attributes[FileAttributeKey.size] as? UInt64 {
            fileSize = currentSize
        } else {
            fileSize = nil
        }

        guard let fileSize else { return }
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        lock.unlock()
        // Public callbacks may synchronously call `finish()` or coordinate with
        // another queue. Never invoke caller code while holding the state lock.
        onChange(fileSize)
    }
}

/// File size changes observer
public class FileSizeObserver {
    /// Target file path
    let url: URL

    /// The dispatch queue used by `DispatchSource`
    let queue: DispatchQueue?

    /// File size changes callback
    let onChange: (_ fileSize: UInt64) -> Void

    private let state: FileSizeObserverState

    /// Initialzie and activate file size change observer
    public init(url: URL, queue: DispatchQueue? = nil, onChange: @escaping (UInt64) -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
        state = FileSizeObserverState(url: url, queue: queue, onChange: onChange)
    }

    /// Close file handle and complete the observer
    public func finish() {
        state.finish()
    }
}
