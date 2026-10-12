// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpeakTyper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "SpeakTyper",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/SpeakTyper"
        ),
    ]
)
