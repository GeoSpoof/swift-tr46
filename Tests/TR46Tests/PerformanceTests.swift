import Dispatch
import Testing

@testable import TR46

/// Inputs large enough that a quadratic stage would run far past a minute, even in a debug build.
/// Each also checks its answer, so a stage that got fast by getting wrong fails too.
///
/// The minute is timed around the work itself, from when it starts running. Swift Testing's
/// `.timeLimit` counts from when a test is scheduled, and in a parallel run on a machine with few
/// cores the CPU-bound suites (DifferentialTests, FastPathTests, PunycodeTests) can hold every
/// thread for longer than that before these tests start. In a 2-CPU Linux VM all six were reported
/// over a one-minute `.timeLimit` at 96.5 s, the moment DifferentialTests finished, though none
/// took more than 7 s of work in a serial debug run on an Apple Silicon Mac. The trait stays, at
/// ten minutes, to stop a runaway test.
@Suite("Performance: no quadratic stage")
struct PerformanceTests {
    /// The bound on each workload, in seconds of wall time from when it starts running.
    static let limit = 60.0

    /// `.timeLimit(.minutes(10))`, a backstop against a test that never finishes. Swift Testing
    /// declares the trait for macOS 13, iOS 16, tvOS 16 and watchOS 9 or later, and SwiftPM builds
    /// a test target for XCTest's minimum OS: macOS 14.0 with Xcode 27, possibly lower with an
    /// older Xcode, where naming the trait directly wouldn't compile. Swift 6.0's `@Suite` doesn't
    /// accept an `@available` suite, so the check is here. Every OS that a supported Xcode runs
    /// tests on has the API, so the backstop applies there.
    static var backstop: any TestTrait {
        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            return .timeLimit(.minutes(10))
        }
        return .enabled(if: true)
    }

    /// Runs `work`, prints how long it took, and records an issue if that was `limit` or more.
    static func withinLimit(_ workload: String, _ work: () throws -> Void) rethrows {
        let start = DispatchTime.now().uptimeNanoseconds
        try work()
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        print("[performance] \(workload): \((seconds * 1_000).rounded() / 1_000) s (limit \(Int(limit)) s)")
        #expect(seconds < limit, "\(workload) took \(seconds) s")
    }

    /// 1,000,000 code points cycling through U+4E00–U+9FA5.
    static let cjk: [UInt32] = (0..<1_000_000).map { 0x4E00 + UInt32($0 % (0x9FA5 - 0x4E00 + 1)) }

    @Test("Punycode encode and decode of a 1,000,000-code-point label", PerformanceTests.backstop)
    func punycodeRoundTrip() throws {
        try Self.withinLimit("Punycode encode and decode, 1,000,000 code points") {
            let encoded = try #require(Punycode.encode(Self.cjk))
            let decoded = try #require(Punycode.decode(encoded.map(UInt32.init)))
            #expect(decoded == Self.cjk)
        }
    }

    @Test("toUnicode of that label's A-label", PerformanceTests.backstop)
    func toUnicodeOfLongALabel() throws {
        try Self.withinLimit("toUnicode of that A-label, with its encoding") {
            let encoded = try #require(Punycode.encode(Self.cjk))
            let result = TR46.toUnicode("xn--" + String(decoding: encoded, as: UTF8.self))
            #expect(!result.hadError)
            #expect(Vectors.codePoints(result.domain) == Self.cjk)
        }
    }

    @Test("NFC of a followed by 200,000 alternating U+0316 and U+0301", PerformanceTests.backstop)
    func nfcLongNonStarterRun() {
        Self.withinLimit("NFC of a + 200,000 U+0316/U+0301") {
            let input: [UInt32] = [0x61] + (0..<200_000).map { $0 % 2 == 0 ? 0x0316 : 0x0301 }
            let output = NFC.normalize(input)
            // Reordered by combining class, then the first U+0301 composes with the a: U+00E1, the
            // 100,000 U+0316 (ccc 220), and the other 99,999 U+0301 (ccc 230).
            let classes = output.dropFirst().map(NFC.combiningClass(of:))
            #expect(output.first == 0xE1)
            #expect(zip(classes, classes.dropFirst()).allSatisfy { $0 <= $1 }, "not sorted by combining class")
            #expect(output == [0xE1] + Array(repeating: 0x0316, count: 100_000) + Array(repeating: 0x0301, count: 99_999))
        }
    }

    @Test("toASCII of 100,000 × U+0628 U+094D U+200C with checkJoiners", PerformanceTests.backstop)
    func contextJLongLabel() throws {
        try Self.withinLimit("toASCII of 100,000 × U+0628 U+094D U+200C, checkJoiners") {
            let input = String(repeating: "\u{0628}\u{094D}\u{200C}", count: 100_000)
            let result = try #require(TR46.toASCII(input, options: TR46.Options(checkJoiners: true)))
            // Each ZWNJ follows a virama, so the label is valid and encodes. None reaches the
            // joining-context scan in Validation.validZWNJ; the next two workloads do.
            #expect(result.hasPrefix("xn--"))
        }
    }

    @Test("toASCII of 100,000 × U+0628 U+200C, then U+0628, with checkJoiners", PerformanceTests.backstop)
    func contextJJoiningContext() throws {
        try Self.withinLimit("toASCII of 100,000 × U+0628 U+200C + U+0628, checkJoiners") {
            let input = String(repeating: "\u{0628}\u{200C}", count: 100_000) + "\u{0628}"
            let result = try #require(TR46.toASCII(input, options: TR46.Options(checkJoiners: true)))
            // U+0628 is Joining_Type D, so every ZWNJ passes on its joining context, each tested on
            // the segment up to the next ZWNJ.
            #expect(result.hasPrefix("xn--"))
        }
    }

    @Test("toASCII of 100,000 virama-allowed ZWNJs, then one checked on joining context", PerformanceTests.backstop)
    func contextJManyEarlierZWNJs() throws {
        try Self.withinLimit("toASCII of U+0628 + 100,000 × U+094D U+200C + U+0628 U+200C U+0628, checkJoiners") {
            let input = "\u{0628}" + String(repeating: "\u{094D}\u{200C}", count: 100_000) + "\u{0628}\u{200C}\u{0628}"
            let result = try #require(TR46.toASCII(input, options: TR46.Options(checkJoiners: true)))
            // The virama allows the first 100,000 ZWNJs without moving the segment's start, so the
            // last ZWNJ's segment holds all of them, and validZWNJ tries each one. Between two of
            // them is only U+094D, Joining_Type T, so each scan has to stop at the neighbouring
            // ZWNJ to stay linear. Only the last one has U+0628 on both sides and passes.
            #expect(result.hasPrefix("xn--"))
        }
    }

    @Test("toASCII of a 1,000,000-character ASCII label", PerformanceTests.backstop)
    func longASCIILabel() {
        Self.withinLimit("toASCII of a 1,000,000-character ASCII label") {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
            let input = (0..<1_000_000).map { alphabet[$0 % alphabet.count] }
            let lowered = input.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }
            let result = TR46.toASCII(String(decoding: input, as: UTF8.self))
            #expect(Vectors.bytes(result) == lowered)
        }
    }

    @Test("toASCII and toUnicode of 200,000 labels \"a.\"", PerformanceTests.backstop)
    func manyLabels() {
        Self.withinLimit("toASCII and toUnicode of 200,000 labels \"a.\"") {
            let input = String(repeating: "a.", count: 200_000)
            #expect(Vectors.sameBytes(TR46.toASCII(input), input))
            let unicode = TR46.toUnicode(input)
            #expect(Vectors.sameBytes(unicode.domain, input) && !unicode.hadError)
        }
    }
}
