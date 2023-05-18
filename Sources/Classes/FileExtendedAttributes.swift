import Foundation
// import CoreLocation

#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif

/// Static methods used to set extended attributes on files
class FileExtendedAttributes {
    // Extended attribute keys
    static let extendedAttributesKey = "NSFileExtendedAttributes"
    static let whereFromsKey = "com.apple.metadata:kMDItemWhereFroms"
    static let customLocationKey = "com.apple.assetsd.customLocation"
    static let originalFilenameKey = "com.apple.assetsd.originalFilename"
    static let assetTypeKey = "com.apple.assetsd.assetType"
    static let durationKey = "com.apple.assetsd.duration"

    /// Set OS file metadata related to media on Apple platform
    /// - Parameters:
    ///   - source: Original file path string
    ///   - destination: Destination file path string
    ///   - fileType: Video file container type
    static func setAppleMetadata(source: URL, destination: URL, copy: Bool, fileType: CompressionFileType) {
        // Apple file system metadata
        let attributes: [String: Any] = [
            Self.assetTypeKey: "video/\(fileType == .mp4 ? "mp4" : "quicktime")".data(using: .utf8)!
            // Self.durationKey: String(format: "%.3f", durationInSeconds).data(using: .utf8)! // String
            // Self.durationKey: Data(bytes: &durationInSeconds, count: MemoryLayout<Double>.size) // Bytes
        ]
        if copy {
            Self.copyAppleMetadata(
                from: source.path,
                to: destination.path,
                customAttributes: attributes
            )
        } else {
            Self.setExtendedAttributes(attributes, ofItemAtPath: destination.path)
        }
    }

    /// Copy selected keys from OS file metadata related to media on Apple platform
    /// - Parameters:
    ///   - source: Original file path string
    ///   - destination: Destination file path string
    ///   - customAttributes: List of extended attributes to be added to file, use with caution
    static func copyAppleMetadata(from source: String, to destination: String, customAttributes: [String: Any] = [:]) {
        // Read source file metadata
        // Can also be read by `xattr -l file.mp4`
        guard let dictionary = try? FileManager.default.attributesOfItem(atPath: source) else {
            // print("No extended attributes found")
            return
        }
        let attributes = NSDictionary(dictionary: dictionary)

        var data: [String: Any] = [:] // selected key-values
        if let extendedAttributes = attributes[extendedAttributesKey] as? [String: Any] {
            // Device/User/URL - com.apple.metadata:kMDItemWhereFroms: bplist00?^Dmitry SXiPhone 13
            if let whereFromData = extendedAttributes[whereFromsKey] as? Data {
                /*if let values = try? PropertyListSerialization.propertyList(from: whereFromData, options: [], format: nil) as? [String] {
                    print("Where from: \(values)") // ["Dmitry S", "iPhone 13"]
                }*/
                data[whereFromsKey] = whereFromData
            }

            // Location - com.apple.assetsd.customLocation: g??j+FB@?;Nё=@
            if let customLocationData = extendedAttributes[customLocationKey] as? Data {
                /*// Coordinates are rounded and stored in first 16 of 64 bytes
                // Real coordinates: 36.54819444444444, 29.11145833333333
                let latitude = Double(customLocationData.withUnsafeBytes { $0.load(as: Double.self) }) // 36.5482
                let longitude = Double(customLocationData.advanced(by: 8).withUnsafeBytes { $0.load(as: Double.self) }) // 29.1116
                print("Location: \(latitude), \(longitude)")

                // INFO: Bytes from 16-24 are probably altitude (com.apple.quicktime.location.altitude) 
                //       but both 000.555 and 031.058 altitude values weren't stored at all (!)
                // print(Double(customLocationData.advanced(by: 16).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0

                // Horizontal Accuracy - 4.766546
                let horizontalAccuracy = Double(customLocationData.advanced(by: 24).withUnsafeBytes { $0.load(as: Double.self) })
                print("Horizontal Accuracy: \(horizontalAccuracy) meters")

                // INFO: Bytes from 32-56 - unknown values stored
                // - verticalAccuracy (com.apple.quicktime.location.accuracy.vertical) - probably 32-40 range
                // - course (com.apple.quicktime.location.speed)
                // - speed (com.apple.quicktime.location.course)
                print(Double(customLocationData.advanced(by: 32).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0
                print(Double(customLocationData.advanced(by: 40).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0
                print(Double(customLocationData.advanced(by: 48).withUnsafeBytes { $0.load(as: Double.self) })) // 0.0

                // Timestamp - 688827791.0 (2022-10-30T13:03:11+0300)
                // Timestamp stored in seconds since reference date - January 1, 2001
                let timestamp = Double(customLocationData.advanced(by: 56).withUnsafeBytes { $0.load(as: Double.self) })
                let date = NSDate(timeIntervalSinceReferenceDate: timestamp)
                print("Date: \(date)") // 2022-10-30 13:03:11 +0000 (time zone lost)

                let bytes = [UInt8](customLocationData)
                let hexString = bytes.map { String(format: "%02x", $0) }.joined()
                print("HEX: \(hexString)")*/
                data[customLocationKey] = customLocationData
            }

            // Original file name - com.apple.assetsd.originalFilename: IMG_3754.MOV 
            if let originalFilenameData = extendedAttributes[originalFilenameKey] as? Data {
                /*if let originalFilename = String(data: originalFilenameData, encoding: .utf8) {
                    print("Original Filename: \(originalFilename)")
                }*/
                data[originalFilenameKey] = originalFilenameData
            }

            // Custom values
            if !customAttributes.isEmpty {
                for (key, value) in customAttributes {
                    data[key] = value
                }
            }

            if !data.isEmpty {
                // Write selected attributes to destination file
                setExtendedAttributes(data, ofItemAtPath: destination)
            }
        } // else { print("No extended attributes found") }
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
}
