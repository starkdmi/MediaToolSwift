import Foundation
import Darwin

private struct FileObjectIdentifier: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let generation: UInt64
}

private enum FileOutputReservationKey: Hashable {
    case entry(parent: FileObjectIdentifier, name: String)
    case fallbackEntry(parent: String, name: String)
    case object(FileObjectIdentifier)
}

private func fileObjectIdentifier(
    at url: URL,
    followingSymbolicLinks: Bool = true
) -> FileObjectIdentifier? {
    var information = stat()
    let flags = followingSymbolicLinks ? 0 : AT_SYMLINK_NOFOLLOW
    let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return -1 }
        return fstatat(AT_FDCWD, path, &information, flags)
    }
    guard result == 0 else { return nil }
    return FileObjectIdentifier(
        device: UInt64(information.st_dev),
        inode: UInt64(information.st_ino),
        generation: UInt64(information.st_gen)
    )
}

private func renamedTombstoneURL(for url: URL) -> URL {
    url.deletingLastPathComponent().appendingPathComponent(
        ".\(url.lastPathComponent).mediatool-delete-\(UUID().uuidString)"
    )
}

/// Removes a directory entry without a check-then-unlink window. The entry is
/// first atomically moved to a private same-directory name, then its identity is
/// checked. A mismatched entry is restored without overwriting anything that
/// appeared at the original pathname in the meantime. If an independent actor
/// claims that pathname before restoration, the entry remains intact at the
/// tombstone URL; pathname transactions cannot provide compare-and-delete
/// semantics against an adversarial concurrent directory mutator.
@discardableResult
private func deleteEntry(
    at url: URL,
    ifIdentityMatches expected: FileObjectIdentifier
) -> Bool {
    let tombstone = renamedTombstoneURL(for: url)
    let moveError = url.withUnsafeFileSystemRepresentation { sourcePath in
        tombstone.withUnsafeFileSystemRepresentation { tombstonePath in
            guard let sourcePath, let tombstonePath else { return EINVAL }
            return renameatx_np(
                AT_FDCWD,
                sourcePath,
                AT_FDCWD,
                tombstonePath,
                UInt32(RENAME_EXCL)
            ) == 0 ? 0 : errno
        }
    }
    guard moveError == 0 else { return false }

    guard fileObjectIdentifier(at: tombstone, followingSymbolicLinks: false) == expected else {
        _ = tombstone.withUnsafeFileSystemRepresentation { tombstonePath in
            url.withUnsafeFileSystemRepresentation { sourcePath in
                guard let tombstonePath, let sourcePath else { return EINVAL }
                return renameatx_np(
                    AT_FDCWD,
                    tombstonePath,
                    AT_FDCWD,
                    sourcePath,
                    UInt32(RENAME_EXCL)
                ) == 0 ? 0 : errno
            }
        }
        return false
    }

    return tombstone.withUnsafeFileSystemRepresentation { path in
        guard let path else { return false }
        return unlink(path) == 0
    }
}

/// Captures the directory entry that supplied a conversion's source data.
///
/// Source deletion is intentionally conditional: a caller or another process
/// may replace the pathname while a conversion is running. Atomically moving
/// the entry aside before comparing its non-following identity prevents the
/// replacement entry from being mistaken for the original source. Following
/// symbolic links here would be incorrect because deleting a source URL removes
/// the link entry, not its target.
internal struct SourceFileIdentity: Sendable {
    private let url: URL
    private let identifier: FileObjectIdentifier

    internal init?(at url: URL) {
        guard let identifier = fileObjectIdentifier(
            at: url,
            followingSymbolicLinks: false
        ) else {
            return nil
        }
        self.url = url
        self.identifier = identifier
    }

    /// Deletes the source only while its pathname still resolves to the entry
    /// captured at setup. Failure remains best-effort for compatibility with
    /// the existing `deleteSourceFile` behavior.
    @discardableResult
    internal func deleteIfUnchanged() -> Bool {
        deleteEntry(at: url, ifIdentityMatches: identifier)
    }
}

/// Builds the reservation name for a destination.
///
/// Canonical mapping is always applied because APFS is normalization
/// insensitive and HFS+ stores decomposed names, so the composed and
/// decomposed spellings of one name address the same entry.
///
/// Case folding is applied only on case-insensitive volumes. Nothing else is
/// folded: diacritic and width insensitivity are not filesystem behaviors and
/// are independent of case sensitivity. `resume.mov` and `résumé.mov` coexist
/// on case-insensitive APFS, so folding them together would make concurrent
/// conversions to those two names collide and spuriously report
/// `destinationFileExists`.
private func normalizedFileName(_ name: String, in parent: URL) -> String {
    let normalized = name.precomposedStringWithCanonicalMapping
    let values = try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
    guard values?.volumeSupportsCaseSensitiveNames == true else {
        return normalized.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
    return normalized
}

private func makeReservationKeys(for destination: URL) -> Set<FileOutputReservationKey> {
    let parent = destination.deletingLastPathComponent()
    let name = normalizedFileName(destination.lastPathComponent, in: parent)
    var keys: Set<FileOutputReservationKey>
    if let parentIdentifier = fileObjectIdentifier(at: parent) {
        keys = [.entry(parent: parentIdentifier, name: name)]
    } else {
        keys = [.fallbackEntry(parent: parent.standardizedFileURL.path, name: name)]
    }
    if let identifier = fileObjectIdentifier(at: destination) {
        keys.insert(.object(identifier))
    }
    return keys
}

/// Returns true when two existing paths resolve to the same filesystem object.
///
/// URL equality is insufficient on case-insensitive volumes and for symbolic
/// or hard-link aliases. `stat` follows those aliases and supplies stable
/// device/inode identity for source/destination safety checks.
internal func fileURLsReferToSameItem(_ first: URL, _ second: URL) -> Bool {
    if first.standardizedFileURL == second.standardizedFileURL {
        return true
    }
    guard let firstIdentifier = fileObjectIdentifier(at: first),
          let secondIdentifier = fileObjectIdentifier(at: second) else {
        return false
    }
    return firstIdentifier == secondIdentifier
}

private final class FileOutputReservationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<FileOutputReservationKey> = []

    func reserve(_ requestedKeys: Set<FileOutputReservationKey>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard keys.isDisjoint(with: requestedKeys) else {
            return false
        }
        keys.formUnion(requestedKeys)
        return true
    }

    func release(_ releasedKeys: Set<FileOutputReservationKey>) {
        lock.lock()
        keys.subtract(releasedKeys)
        lock.unlock()
    }
}

/// Writes a conversion beside its requested destination and publishes it only
/// after the encoder has completed successfully.
///
/// Keeping the working file on the same volume allows an atomic rename to
/// preserve the caller's previous destination until final publication.
internal final class FileOutputTransaction {
    private static let reservations = FileOutputReservationRegistry()

    let destinationURL: URL
    let outputURL: URL
    let destinationExisted: Bool
    private let destinationIdentifier: FileObjectIdentifier?
    private let reservationKeys: Set<FileOutputReservationKey>
    private var ownsReservation = false
    private var outputIdentifier: FileObjectIdentifier?

    init(destination: URL, overwrite: Bool) throws {
        destinationURL = destination
        destinationExisted = FileManager.default.fileExists(atPath: destination.path)
        destinationIdentifier = fileObjectIdentifier(
            at: destination,
            followingSymbolicLinks: false
        )

        guard !destinationExisted || overwrite else {
            throw CompressionError.destinationFileExists
        }
        if destinationExisted {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(
                atPath: destination.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                throw CompressionError.cannotOverWrite
            }
        }

        let fileExtension = destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        let temporaryName = ".\(stem).mediatool-\(UUID().uuidString)"
        var outputURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(temporaryName)
        if !fileExtension.isEmpty {
            outputURL.appendPathExtension(fileExtension)
        }
        self.outputURL = outputURL
        reservationKeys = makeReservationKeys(for: destination)

        guard Self.reservations.reserve(reservationKeys) else {
            throw CompressionError.destinationFileExists
        }
        ownsReservation = true
    }

    deinit {
        discard()
    }

    func commit() throws {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.cannotOverWrite
        }

        captureOutputIdentityIfPresent()
        if destinationExisted {
            try replaceExistingDestination()
        } else {
            try publishNewDestination()
        }
        releaseReservation()
    }

    private func replaceExistingDestination() throws {
        guard let destinationIdentifier, let outputIdentifier else {
            throw CompressionError.cannotOverWrite
        }
        let errorCode = outputURL.withUnsafeFileSystemRepresentation { sourcePath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    return EINVAL
                }
                return renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_SWAP)
                ) == 0 ? 0 : errno
            }
        }
        guard errorCode == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode))
        }

        let displacedMatches = fileObjectIdentifier(
            at: outputURL,
            followingSymbolicLinks: false
        ) == destinationIdentifier
        let publishedMatches = fileObjectIdentifier(
            at: destinationURL,
            followingSymbolicLinks: false
        ) == outputIdentifier
        guard displacedMatches, publishedMatches else {
            _ = outputURL.withUnsafeFileSystemRepresentation { sourcePath in
                destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let sourcePath, let destinationPath else { return EINVAL }
                    return renameatx_np(
                        AT_FDCWD,
                        sourcePath,
                        AT_FDCWD,
                        destinationPath,
                        UInt32(RENAME_SWAP)
                    ) == 0 ? 0 : errno
                }
            }
            throw CompressionError.cannotOverWrite
        }
        // The new output is live at the destination from here on, so publication
        // has succeeded. Removing the displaced original is cleanup and is
        // deliberately best-effort: reporting a failed conversion for a
        // completed publication would be wrong, and leaves callers unable to
        // tell whether the destination was replaced. A failure here only leaves
        // the previous file behind under the transaction's hidden temporary
        // name.
        self.outputIdentifier = nil
        deleteEntry(at: outputURL, ifIdentityMatches: destinationIdentifier)
    }

    private func publishNewDestination() throws {
        let errorCode = outputURL.withUnsafeFileSystemRepresentation { sourcePath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    return EINVAL
                }
                return renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                ) == 0 ? 0 : errno
            }
        }
        if errorCode == EEXIST {
            throw CompressionError.destinationFileExists
        }
        guard errorCode == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode))
        }
        outputIdentifier = nil
    }

    func discard() {
        if let outputIdentifier {
            _ = deleteEntry(at: outputURL, ifIdentityMatches: outputIdentifier)
        }
        releaseReservation()
    }

    func captureOutputIdentityIfPresent() {
        guard outputIdentifier == nil else { return }
        outputIdentifier = fileObjectIdentifier(
            at: outputURL,
            followingSymbolicLinks: false
        )
    }

    private func releaseReservation() {
        guard ownsReservation else { return }
        ownsReservation = false
        Self.reservations.release(reservationKeys)
    }
}
