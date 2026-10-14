// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "AbsoluteCore", targets: ["AbsoluteCore"]),
    .library(name: "AbsoluteMach", targets: ["AbsoluteMach"]),
    .executable(name: "absolute", targets: ["AbsoluteCLI"])
]
var targets: [Target] = [
    .target(name: "AbsoluteCore"),
    .target(name: "AbsoluteMach"),
    .executableTarget(name: "AbsoluteCLI", dependencies: ["AbsoluteCore", "AbsoluteMach"]),
    .testTarget(name: "AbsoluteCoreTests", dependencies: ["AbsoluteCore"]),
    .testTarget(name: "AbsoluteMachTests", dependencies: ["AbsoluteMach"], resources: [.copy("Fixtures")])
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
