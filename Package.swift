// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CamPrompt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CamPrompt", targets: ["CamPrompt"])
    ],
    targets: [
        .executableTarget(
            name: "CamPrompt",
            path: "Sources/CamPrompt"
        )
    ]
)
