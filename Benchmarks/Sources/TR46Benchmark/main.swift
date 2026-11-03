// Throughput of the public API on the workloads of plan.md §12, timed with ContinuousClock:
//
//   swift run -c release --package-path Benchmarks TR46Benchmark
//
// It prints operations per second and nanoseconds per operation, and has no thresholds: the
// numbers depend on the machine. CI builds this package but doesn't run it. The quadratic-input
// guards are PerformanceTests in the library's own tests.

import TR46

/// The URL Standard's "domain to ASCII" options, as whatwg-url passes them to tr46.
let urlOptions = TR46.Options(checkBidi: true, checkJoiners: true)

let asciiHostnames = [
    "example.com", "www.apple.com", "github.com", "en.wikipedia.org", "mail.google.com", "static.example.co.uk",
]
let idnHostnames = ["münchen.de", "пример.рф", "例え.jp"]
let aLabels = idnHostnames.map { TR46.toASCII($0, options: urlOptions)! }

/// 64,000 code points cycling through U+4E00–U+9FA5, and its A-label.
let longLabel = String(String.UnicodeScalarView((0..<64_000).map { Unicode.Scalar(0x4E00 + UInt32($0 % 20_902))! }))
let longALabel = TR46.toASCII(longLabel)!

/// `value` with thousands separators.
func grouped(_ value: Int) -> String {
    let digits = String(value)
    var result = ""
    for (index, digit) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 { result += "," }
        result.append(digit)
    }
    return result
}

func padded(_ text: String, _ width: Int, right: Bool = false) -> String {
    let padding = String(repeating: " ", count: max(0, width - text.count))
    return right ? padding + text : text + padding
}

/// Runs `body` repeatedly for at least half a second, after one untimed run, and prints the rate.
/// `body` returns the number of bytes it produced, which is summed so that no call can be
/// optimized away; `operations` is how many API calls one run makes.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
func measure(_ name: String, operations: Int, _ body: () -> Int) {
    let clock = ContinuousClock()
    var produced = body()
    var runs = 0
    let start = clock.now
    var elapsed = Duration.zero
    repeat {
        produced &+= body()
        runs += 1
        elapsed = clock.now - start
    } while elapsed < .milliseconds(500)
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let count = Double(runs * operations)
    let tenthsOfNanoseconds = Int((seconds / count * 1e10).rounded())
    print(
        padded(name, 54)
            + padded(grouped(Int((count / seconds).rounded())), 14, right: true) + " ops/s"
            + padded("\(grouped(tenthsOfNanoseconds / 10)).\(tenthsOfNanoseconds % 10)", 14, right: true) + " ns/op"
    )
    if produced == 0 { print("  (\(name) produced nothing)") }
}

if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
    print("TR46Benchmark: tr46 \(TR46.upstreamVersion), Unicode \(TR46.unicodeVersion)")
    print("Options: the URL Standard's (checkBidi, checkJoiners), or tr46's defaults where marked.")
    print("IDN hostnames: \(idnHostnames.joined(separator: ", ")). Long label: U+4E00–U+9FA5, cycled.")
    measure("toASCII, ASCII hostnames", operations: asciiHostnames.count) {
        asciiHostnames.reduce(0) { $0 + (TR46.toASCII($1, options: urlOptions)?.utf8.count ?? 0) }
    }
    measure("toASCII, IDN hostnames", operations: idnHostnames.count) {
        idnHostnames.reduce(0) { $0 + (TR46.toASCII($1, options: urlOptions)?.utf8.count ?? 0) }
    }
    measure("toUnicode, their A-labels", operations: aLabels.count) {
        aLabels.reduce(0) { $0 + TR46.toUnicode($1, options: urlOptions).domain.utf8.count }
    }
    measure("toASCII, a 64,000-code-point label (encode), defaults", operations: 1) {
        TR46.toASCII(longLabel)?.utf8.count ?? 0
    }
    measure("toUnicode, its A-label (decode), defaults", operations: 1) {
        TR46.toUnicode(longALabel).domain.utf8.count
    }
} else {
    print("TR46Benchmark needs ContinuousClock: macOS 13, iOS 16, tvOS 16 or watchOS 9 or later")
}
