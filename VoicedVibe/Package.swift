// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoicedVibe",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "VoicedVibe",
            path: "Sources/VoicedVibe",
            resources: [
                .copy("Resources/backend"),
            ]
        )
    ]
)
