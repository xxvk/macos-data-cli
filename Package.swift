// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "macos-data-cli",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .library(
            name: "ContactsAdapter",
            targets: ["ContactsAdapter"]
        ),
        .executable(
            name: "macos-data",
            targets: ["macos-data"]
        )
    ],
    targets: [
        .target(
            name: "Core",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ContactsAdapter",
            dependencies: ["Core"],
            path: "Sources/Contacts",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "macos-data",
            dependencies: ["Core", "ContactsAdapter"],
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-sectcreate",
                    "-Xlinker",
                    "__TEXT",
                    "-Xlinker",
                    "__info_plist",
                    "-Xlinker",
                    "Sources/macos-data/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ContactsTests",
            dependencies: ["ContactsAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["macos-data"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
