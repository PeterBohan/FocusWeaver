// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FocusWeaverMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FocusWeaverMac",
            targets: ["FocusWeaverMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FocusWeaverMac",
            exclude: [
                "Resources"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FocusWeaverMac/Resources/Info.plist"
                ])
            ]
        )
    ]
)
