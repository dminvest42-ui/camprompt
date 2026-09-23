// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CamPrompt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CamPrompt", targets: ["CamPrompt"])
    ],
    targets: [
        // Tiny Objective-C shim: catches NSException from AVFoundation so a
        // rejected recording setting falls back instead of crashing.
        // Our own code, not an external dependency (DECISIONS D-020).
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher"
        ),
        .executableTarget(
            name: "CamPrompt",
            dependencies: ["ObjCExceptionCatcher"],
            path: "Sources/CamPrompt"
        )
    ]
)
