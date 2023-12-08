import CoreLocation

/// Additional media information
public struct ExtendedFileInfo {
    /// Public initializer
    public init(
        // date: Date?,
        location: CLLocation?,
        whereFrom: [String]?,
        originalFilename: String?
        // filesize: Int64?
    ) {
        // self.date = date
        self.location = location
        self.whereFrom = whereFrom
        self.originalFilename = originalFilename
        // self.filesize = filesize
    }

    // Original date
    // public let date: Date?

    /// Location
    public let location: CLLocation?

    /// Where from
    public let whereFrom: [String]?

    /// Original file name
    public let originalFilename: String?

    // File size
    // public let filesize: Int64?
}
