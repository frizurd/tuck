// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tuck", targets: ["Tuck"])],
    targets: [
        .target(name: "TuckCore"),
        .target(name: "TuckPrivate"),
        .executableTarget(name: "Tuck", dependencies: ["TuckCore", "TuckPrivate"]),
        .testTarget(name: "TuckCoreTests", dependencies: ["TuckCore"])
    ]
)
