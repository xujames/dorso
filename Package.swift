// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Posturr",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Posturr",
            path: ".",
            sources: ["main.swift"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage")
            ]
        )
    ]
)
