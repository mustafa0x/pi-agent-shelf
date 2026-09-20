// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PiAgentShelf",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PiAgentShelf", targets: ["PiAgentShelf"]),
    ],
    targets: [
        .executableTarget(name: "PiAgentShelf"),
        .testTarget(name: "PiAgentShelfTests", dependencies: ["PiAgentShelf"]),
    ],
    swiftLanguageModes: [.v5]
)
