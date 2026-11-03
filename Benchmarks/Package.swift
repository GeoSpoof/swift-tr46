// swift-tools-version: 6.0
import PackageDescription

// The benchmark is a package of its own, so the library's manifest keeps one product, one target
// and one test target, and a package that depends on swift-tr46 never sees an executable.
//
//   swift run -c release --package-path Benchmarks TR46Benchmark
let package = Package(
    name: "TR46Benchmarks",
    dependencies: [
        // Named, because a path dependency otherwise takes its identity from the directory name,
        // and a clone in a directory not called swift-tr46 would then fail to resolve.
        .package(name: "swift-tr46", path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "TR46Benchmark",
            dependencies: [.product(name: "TR46", package: "swift-tr46")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
