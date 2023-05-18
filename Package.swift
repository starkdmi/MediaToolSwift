// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "MediaToolSwift",
    platforms: [
        .macOS(.v11), .iOS(.v13)
    ],
    products: [
        .library(name: "MediaToolSwift", targets: ["MediaToolSwift"])
    ],
    /*dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.2.0")
    ],*/
    targets: [
        .target(
            name: "MediaToolSwift",
            dependencies: [
                "ObjCExceptionCatcher"
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
        .testTarget(name: "MediaToolSwiftTests", dependencies: ["MediaToolSwift"], path: "Tests")
    ]
)
