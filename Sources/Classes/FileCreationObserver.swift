//
//  FileCreationObserver.swift
//  
//
//  Created by Dmitry Starkov on 18/03/2024.
//

import Foundation

/// Directory new file creation observer
/*internal class FileCreationObserver {
    /// Target directory path
    let url: URL

    /// Filter by prefix
    let prefix: String?

    /// Filter by file extension
    let ext: String?

    /// Filter by quarantine file attribute, compare to bundle name, `nil` to disable
    let quarantine: String?

    /// The dispatch queue used by `DispatchSource`
    let queue: DispatchQueue?

    /// File created callback
    let completion: (_ file: URL) -> Void

    private var source: DispatchSourceFileSystemObject?

    /// Initialize and activate file creation observer
    init(
        url: URL,
        prefix: String? = "Remaker-",
        ext: String? = "", // empty extension
        quarantine: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
        queue: DispatchQueue? = nil,
        completion: @escaping (URL) -> Void
    ) {
        self.url = url
        self.prefix = prefix
        self.ext = ext
        self.quarantine = quarantine
        self.queue = queue
        self.completion = completion

        // Directory descriptor
        let fileDescriptor = open(url.path, O_EVTONLY)
        // guard fileDescriptor >= 0 else { return }

        // Init file create observer
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )

        // Detect new files in events
        let startTime = Date()
        var cached: Set<URL> = []
        self.source?.setEventHandler { [weak self] in
            guard let self = self else { return }

            // Get newest file in directory
            if self.source?.data == .write {
                // List files in directory
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.creationDateKey, .quarantinePropertiesKey],
                    options: .skipsHiddenFiles
                ) else { return }

                // Skip cached items
                var unique: [URL] = []
                for item in urls {
                    if cached.insert(item).inserted {
                        unique.append(item)
                    }
                }

                // Filter and sort
                let files = unique.filter({ fileURL in
                    guard let attributes = try? fileURL.resourceValues(forKeys: [.creationDateKey, .quarantinePropertiesKey]),
                          let creationDate = attributes.creationDate else {
                        return false
                    }

                    // Check the prefix
                    if let prefix = prefix {
                        guard fileURL.lastPathComponent.starts(with: prefix) else { return false }
                    }

                    // Check the extension
                    if let ext = ext {
                        guard fileURL.pathExtension == ext else { return false }
                    }

                    // File name is `Remaker-5iuQIV`
                    // Command `xattr -l Remaker-5iuQIV` shows file is quarantined (flag;date;app_name;UUID;)
                    // com.apple.quarantine: 0082;62f5b22c;MediaToolSwift;
                    // debugPrint(attributes.quarantineProperties)
                    /* [String: Any] = [
                        "LSQuarantineTimeStamp": 2024-01-01 12:00:00 +0000,
                        "LSQuarantineType": LSQuarantineTypeSandboxed,
                        "LSQuarantineIsOwnedByCurrentUser": 1,
                        "LSQuarantineAgentName": MediaToolSwift
                     ]*/
                    if let quarantine = quarantine, let quarantineAttributes = attributes.quarantineProperties {
                        guard quarantineAttributes[kLSQuarantineAgentNameKey as String] as? String == quarantine else { return false }
                    }

                    // Filter by creation date
                    // return creationDate.compare(startTime) != .orderedAscending
                    return creationDate >= startTime
                }).sorted(by: {
                    // Sort by creation date
                    guard let date1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false }
                    guard let date2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate else { return true }
                    return date1 > date2
                })
                guard !files.isEmpty else { return }

                // Pass more recent file
                completion(files[0])
            }
        }

        // Prepare for cleanup call
        self.source?.setCancelHandler {
            close(fileDescriptor)
        }

        // Run observer
        self.source?.activate() // .resume()
    }

    /// Deinitialize
    deinit {
        self.finish()
    }

    /// Close file descriptor and complete the observer
    public func finish() {
        self.source?.cancel()
    }
}*/

/// File Observer Configuration
internal enum FileObserverConfig: Equatable {
    /// Only observe files larger than `minimalFileLenght`, in KB
    static let minimalFileLenght: Double = 25_000

    /// Do not observe file lenght in any case
    case disabled

    /// Observe fully matching destination path
    case matching

    /// Observe new file created in specified directory
    // case directory(path: URL)

    /// Create temporary empty directory and observe any new file creation
    /// Temporary directory will be removed on completion or failure
    // case temp(path: URL)

    /// Equatable conformance
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled):
            return true
        case (.matching, .matching):
            return true
        /*case let (.directory(lhsPath), .directory(rhsPath)):
            return lhsPath == rhsPath
        case let (.temp(lhsPath), .temp(rhsPath)):
            return lhsPath == rhsPath*/
        default:
            return false
        }
    }
}
