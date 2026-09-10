// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuTune",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MenuTune", targets: ["MenuTune"])],
    targets: [
        .target(name: "MenuTuneCore"),
        .executableTarget(name: "MenuTune", dependencies: ["MenuTuneCore"], resources: [.process("Resources")]),
        .testTarget(name: "MenuTuneCoreTests", dependencies: ["MenuTuneCore"]),
        .testTarget(name: "MenuTuneTests", dependencies: ["MenuTune", "MenuTuneCore"])
    ],
    swiftLanguageModes: [.v5]
)
