// swift-tools-version: 6.0
import PackageDescription

// No `platforms:` on purpose. The library uses only the standard library, plus Foundation's
// precomposedStringWithCanonicalMapping on Apple platforms, so the toolchain's own minimums are the
// floors, and a declared floor would only add deprecation warnings on newer Xcode.
let package = Package(
    name: "swift-tr46",
    products: [
        .library(name: "TR46", targets: ["TR46"]),
    ],
    targets: [
        .target(name: "TR46"),
        .testTarget(
            name: "TR46Tests",
            dependencies: ["TR46"],
            resources: [.copy("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
