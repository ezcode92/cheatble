// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cheatble",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Cheatble", targets: ["Cheatble"])],
    targets: [
        .target(name: "CheatbleCore", resources: [.process("Resources/Shortcuts.json"), .copy("Resources/Packs")]),
        .executableTarget(name: "Cheatble", dependencies: ["CheatbleCore"]),
        .testTarget(name: "CheatbleCoreTests", dependencies: ["CheatbleCore"])
    ]
)
