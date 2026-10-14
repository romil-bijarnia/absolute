// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AbsoluteLinux",
    products: [.executable(name: "AbsoluteLinux", targets: ["AbsoluteLinux"])],
    dependencies: [.package(name: "Absolute", path: "..")],
    targets: [
        .systemLibrary(name: "CGTK", pkgConfig: "gtk4", providers: [.apt(["libgtk-4-dev"])]),
        .systemLibrary(name: "CGioUnix", pkgConfig: "gio-unix-2.0", providers: [.apt(["libglib2.0-dev"])]),
        .target(name: "DesktopToolkit", dependencies: ["CGTK", "CGioUnix"]),
        .executableTarget(name: "AbsoluteLinux", dependencies: [
            "DesktopToolkit", .product(name: "AbsoluteCore", package: "Absolute")
        ])
    ]
)
