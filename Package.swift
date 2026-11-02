// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tuck", targets: ["Tuck"])],
    targets: [
        .target(name: "TuckCore"),
        .executableTarget(name: "Tuck", dependencies: ["TuckCore"]),
        .testTarget(name: "TuckCoreTests", dependencies: ["TuckCore"])
    ]
)
