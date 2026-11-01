// swift-tools-version:6.0
import PackageDescription

// Unit tests for the plain Swift logic behind mobile-ui's iOS renderers, the
// parts that need neither SwiftUI nor the core app. Sources are linked from
// resources/ios so the tests run the shipped code.
let package = Package(
    name: "NativeUILogic",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "NativeUILogic", path: "Sources/NativeUILogic"),
        .testTarget(name: "NativeUILogicTests", dependencies: ["NativeUILogic"], path: "Tests/NativeUILogicTests"),
    ]
)
