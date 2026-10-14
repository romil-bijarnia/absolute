// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "AbsoluteCore", targets: ["AbsoluteCore"]),
    .executable(name: "absolute", targets: ["AbsoluteCLI"])
]
var targets: [Target] = [
    .target(name: "AbsoluteCore"),
    .executableTarget(name: "AbsoluteCLI", dependencies: ["AbsoluteCore"]),
    .testTarget(name: "AbsoluteCoreTests", dependencies: ["AbsoluteCore"])
]

#if os(macOS)
products.append(.executable(name: "AbsoluteDesktop", targets: ["AbsoluteDesktop"]))
targets.append(.executableTarget(name: "AbsoluteDesktop", dependencies: ["AbsoluteCore"]))
#endif

let package = Package(
    name: "Absolute",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
