// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mpia-cli",
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
        .library(
            name: "MailAdapter",
            targets: ["MailAdapter"]
        ),
        .library(
            name: "CalendarAdapter",
            targets: ["CalendarAdapter"]
        ),
        .library(
            name: "RemindersAdapter",
            targets: ["RemindersAdapter"]
        ),
        .library(
            name: "PhotosAdapter",
            targets: ["PhotosAdapter"]
        ),
        .library(
            name: "NotesAdapter",
            targets: ["NotesAdapter"]
        ),
        .library(
            name: "ShortcutsAdapter",
            targets: ["ShortcutsAdapter"]
        ),
        .library(
            name: "SafariAdapter",
            targets: ["SafariAdapter"]
        ),
        .executable(
            name: "mpia",
            targets: ["mpia"]
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
        .target(
            name: "MailAdapter",
            dependencies: ["Core"],
            path: "Sources/Mail",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "CalendarAdapter",
            dependencies: ["Core"],
            path: "Sources/Calendar",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "RemindersAdapter",
            dependencies: ["Core"],
            path: "Sources/Reminders",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "PhotosAdapter",
            dependencies: ["Core"],
            path: "Sources/Photos",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "NotesAdapter",
            dependencies: ["Core"],
            path: "Sources/Notes",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ShortcutsAdapter",
            dependencies: ["Core"],
            path: "Sources/Shortcuts",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "SafariAdapter",
            dependencies: ["Core"],
            path: "Sources/Safari",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "mpia",
            dependencies: ["Core", "ContactsAdapter", "MailAdapter", "CalendarAdapter", "RemindersAdapter", "PhotosAdapter", "NotesAdapter", "ShortcutsAdapter", "SafariAdapter"],
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
                    "Sources/mpia/Info.plist"
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
            name: "MailTests",
            dependencies: ["MailAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CalendarTests",
            dependencies: ["CalendarAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RemindersTests",
            dependencies: ["RemindersAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PhotosTests",
            dependencies: ["PhotosAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NotesTests",
            dependencies: ["NotesAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ShortcutsTests",
            dependencies: ["ShortcutsAdapter"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SafariTests",
            dependencies: ["SafariAdapter", "Core"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["mpia"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
