// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GuitarTab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GuitarTab", targets: ["GuitarTab"])],
    targets: [
        .executableTarget(name: "GuitarTab"),
        .testTarget(name: "GuitarTabTests", dependencies: ["GuitarTab"])
    ],
    swiftLanguageModes: [.v5]
)
