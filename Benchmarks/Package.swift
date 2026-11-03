// swift-tools-version: 6.0
import PackageDescription

// The benchmark is a package of its own, so the library's manifest keeps one product, one target
// and one test target, and a package that depends on swift-tr46 never sees an executable.
//
//   swift run -c release --package-path Benchmarks TR46Benchmark
let package = Package(
    name: "TR46Benchmarks",
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "TR46Benchmark",
            dependencies: [.product(name: "TR46", package: "swift-tr46")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
