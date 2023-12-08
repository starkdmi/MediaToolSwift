import Foundation
import CoreLocation

#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Static methods used to set extended attributes on files
internal class FileExtendedAttributes {
    // Extended attribute keys
    static let extendedAttributesKey = "NSFileExtendedAttributes"
    static let whereFromsKey = "com.apple.metadata:kMDItemWhereFroms"
    static let customLocationKey = "com.apple.assetsd.customLocation"
    static let originalFilenameKey = "com.apple.assetsd.originalFilename"
    static let assetTypeKey = "com.apple.assetsd.assetType"
    static let durationKey = "com.apple.assetsd.duration"

    /// Set extended file metadata related to media on Apple platform
    /// - Parameters:
    ///   - source: Original file path string
    ///   - destination: Destination file path string
    ///   - copy: Flag to copy metadata from source to destination
    ///   - fileType: Video file container type
    static func setExtendedMetadata(
        source: URL,
        destination: URL,
        copy: Bool,
        fileType: VideoFileType
    ) -> [String: Data] {
        // Apple file system metadata
        let attributes: [String: Data] = [
            Self.assetTypeKey: "video/\(fileType == .mp4 ? "mp4" : "quicktime")".data(using: .utf8)!
            // Self.durationKey: String(format: "%.3f", durationInSeconds).data(using: .utf8)! // String
            // Self.durationKey: Data(bytes: &durationInSeconds, count: MemoryLayout<Double>.size) // Bytes
        ]

        if copy {
            return Self.copyExtendedMetadata(
                from: source.path,
                to: destination.path,
                customAttributes: attributes
            )
        } else {
            Self.setExtendedAttributes(attributes, ofItemAtPath: destination.path)
            return attributes
        }
    }

    /// Copy selected keys from extended file metadata related to media on Apple platform
    /// - Parameters:
    ///   - source: Original file path string
    ///   - destination: Destination file path string
    ///   - customAttributes: List of extended attributes to be added to file, use with caution
    static func copyExtendedMetadata(
        from source: String,
        to destination: String,
        customAttributes: [String: Data] = [:]
    ) -> [String: Data] {
        // Get source metadata
        var data = getExtendedMetadata(from: source)

        // Insert custom values
        if !customAttributes.isEmpty {
            for (key, value) in customAttributes {
                data[key] = value
            }
        }

        if !data.isEmpty {
            // Write selected attributes to destination file
            setExtendedAttributes(data, ofItemAtPath: destination)
        }

        return data
    }

    /// Retvieve extended file metadata
    /// - Parameters:
    ///   - source: Original file path string
    static func getExtendedMetadata(from source: String) -> [String: Data] {
        var data: [String: Data] = [:]

        // Read source file metadata
        // Can also be read by `xattr -l file.mp4`
        guard let dictionary = try? FileManager.default.attributesOfItem(atPath: source) else {
            return data
        }

        // Get the dictionary
        let attributes = NSDictionary(dictionary: dictionary)
        guard let extendedAttributes = attributes[extendedAttributesKey] as? [String: Any] else {
            return data
        }

        // Where from
        if let whereFromData = extendedAttributes[whereFromsKey] as? Data {
            data[whereFromsKey] = whereFromData
        }

        // Location
        if let customLocationData = extendedAttributes[customLocationKey] as? Data {
            data[customLocationKey] = customLocationData
        }

        // Filename
        if let originalFilenameData = extendedAttributes[originalFilenameKey] as? Data {
            data[originalFilenameKey] = originalFilenameData
        }

        return data
    }

    /// Safely set extended attributes
    /// - Parameters:
    ///   - attributes: List of extended attributes to add
    ///   - ofItemAtPath: File path string
    static func setExtendedAttributes(_ attributes: [String: Any], ofItemAtPath path: String) {
        do {
            try ObjCExceptionCatcher.catchException {
                // Can raise NSInvalidArgumentException for incorrect data types
                try? FileManager.default.setAttributes([
                    .init(rawValue: Self.extendedAttributesKey): attributes
                ], ofItemAtPath: path)
            }
        } catch { }
    }

    /// Decode file extended media keys from `Data` objects
    static func extractExtendedFileInfo(from data: [String: Data]) -> ExtendedFileInfo {
        var location: CLLocation?
        var whereFrom: [String]?
        var originalFilename: String?

        for (key, value) in data {
            switch key {
            case FileExtendedAttributes.customLocationKey:
                // Location - com.apple.assetsd.customLocation: g??j+FB@?;Nё=@

                // Coordinates are rounded and stored in first 16 of 64 bytes
                // Real coordinates: 36.54819444444444, 29.11145833333333
                let latitude = Double(value.withUnsafeBytes { $0.load(as: Double.self) }) // 36.5482
                let longitude = Double(value.advanced(by: 8).withUnsafeBytes { $0.load(as: Double.self) }) // 29.1116
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                // print("Location: \(latitude), \(longitude)")

                // INFO: Bytes from 16-24 are probably altitude (com.apple.quicktime.location.altitude)
                //       but both 000.555 and 031.058 altitude values weren't stored at all (!)
                // print(Double(customLocationData.advanced(by: 16).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0

                // Horizontal Accuracy - 4.766546
                let horizontalAccuracy = Double(value.advanced(by: 24).withUnsafeBytes { $0.load(as: Double.self) })
                // print("Horizontal Accuracy: \(horizontalAccuracy) meters")

                // INFO: Bytes from 32-56 - unknown values stored
                // - verticalAccuracy (com.apple.quicktime.location.accuracy.vertical) - probably 32-40 range
                // - course (com.apple.quicktime.location.speed)
                // - speed (com.apple.quicktime.location.course)
                // print(Double(value.advanced(by: 32).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0
                // print(Double(value.advanced(by: 40).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0
                // print(Double(value.advanced(by: 48).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0

                // Timestamp - 688827791.0 (2022-10-30T13:03:11+0300)
                // Timestamp stored in seconds since reference date - January 1, 2001
                let timestamp = Double(value.advanced(by: 56).withUnsafeBytes { $0.load(as: Double.self) })
                let date = NSDate(timeIntervalSinceReferenceDate: timestamp) as Date
                // print("Date: \(date)") // 2022-10-30 13:03:11 +0000 (time zone lost)

                // let bytes = [UInt8](value)
                // let hexString = bytes.map { String(format: "%02x", $0) }.joined()
                // print("HEX: \(hexString)")

                location = CLLocation(
                    coordinate: coordinate,
                    altitude: .zero,
                    horizontalAccuracy: horizontalAccuracy,
                    verticalAccuracy: .zero,
                    timestamp: date
                )
            case FileExtendedAttributes.whereFromsKey:
                // Device/User/URL - com.apple.metadata:kMDItemWhereFroms: bplist00?^Dmitry SXiPhone 13
                if let values = try? PropertyListSerialization.propertyList(from: value, options: [], format: nil) as? [String] {
                    whereFrom = values // ["Dmitry S", "iPhone 13"]
                }
            case FileExtendedAttributes.originalFilenameKey:
                // Original file name - com.apple.assetsd.originalFilename: IMG_3754.MOV
                if let filename = String(data: value, encoding: .utf8) {
                    originalFilename = filename
                }
            default:
                break
            }
        }

        return ExtendedFileInfo(
            location: location,
            whereFrom: whereFrom,
            originalFilename: originalFilename
        )
    }
}
