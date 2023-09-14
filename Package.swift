// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MediaToolSwift",
    platforms: [
        .macOS(.v11), .iOS(.v13), .tvOS(.v13)
    ],
    products: [
        .library(name: "MediaToolSwift", targets: ["MediaToolSwift"])
    ],
    dependencies: [
        // To build documentation for Github Pages use:
        // swift package --allow-writing-to-directory ./docs generate-documentation --target MediaToolSwift --disable-indexing --transform-for-static-hosting --hosting-base-path MediaToolSwift --output-path ./docs
        // To preview documentation: swift package --disable-sandbox preview-documentation
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.2.0"),

        .package(url: "https://github.com/SDWebImage/SDWebImageWebPCoder.git", from: "0.13.0")
    ],
    targets: [
        .target(
            name: "MediaToolSwift",
            dependencies: [
                "ObjCExceptionCatcher",
                "SDWebImageWebPCoder"
            ],
            path: "Sources",
            exclude: [
                "Classes/ObjCExceptionCatcher"
            ]
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
                "media"
            ]
        )
    ]
)
