// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MediaToolSwift",
    platforms: [
        .macOS(.v12), .iOS(.v15), .tvOS(.v15), .macCatalyst("15.0"), .visionOS(.v1)
    ],
    products: [
        .library(name: "MediaToolSwift", targets: ["MediaToolSwift"])
    ],
    dependencies: [
        // To build documentation for Github Pages use:
        // swift package --allow-writing-to-directory ./docs generate-documentation --exclude-extended-types --target MediaToolSwift --disable-indexing --transform-for-static-hosting --hosting-base-path MediaToolSwift --output-path ./docs
        // To preview documentation: swift package --disable-sandbox preview-documentation
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "MediaToolSwift",
            dependencies: [
                "ObjCExceptionCatcher"
            ],
            path: "Sources",
            exclude: [
                "Classes/ObjCExceptionCatcher"
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")]
            // swiftSettings: [
            //     .unsafeFlags(["-DADVANCED", "-DIMAGEPLUS"])
            // ]
        ),
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/Classes/ObjCExceptionCatcher",
            exclude: [],
            sources: [
                "ObjCExceptionCatcher.h",
                "ObjCExceptionCatcher.m"
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .linkedLibrary("objc")
            ]
        ),
        .testTarget(
            name: "MediaToolSwiftTests",
            dependencies: ["MediaToolSwift"],
            path: "Tests",
            exclude: [
                "media",
                "README.md"
            ],
            resources: [.copy("ColorFixtures")]
        ),
        .testTarget(
            name: "MediaToolSwiftClientTests",
            dependencies: ["MediaToolSwift"],
            path: "ClientTests"
        )
    ]
)
