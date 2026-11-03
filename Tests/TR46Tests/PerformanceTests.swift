import Testing

@testable import TR46

/// Inputs large enough that a quadratic stage would run far past the one-minute limit, even in a
/// debug build (plan.md §12). Each also checks its answer, so a stage that got fast by getting
/// wrong fails too.
@Suite("Performance: no quadratic stage")
struct PerformanceTests {
    /// 1,000,000 code points cycling through U+4E00–U+9FA5.
    static let cjk: [UInt32] = (0..<1_000_000).map { 0x4E00 + UInt32($0 % (0x9FA5 - 0x4E00 + 1)) }

    @Test("Punycode encode and decode of a 1,000,000-code-point label", .timeLimit(.minutes(1)))
    func punycodeRoundTrip() throws {
        let encoded = try #require(Punycode.encode(Self.cjk))
        let decoded = try #require(Punycode.decode(encoded.map(UInt32.init)))
        #expect(decoded == Self.cjk)
    }

    @Test("toUnicode of that label's A-label", .timeLimit(.minutes(1)))
    func toUnicodeOfLongALabel() throws {
        let encoded = try #require(Punycode.encode(Self.cjk))
        let result = TR46.toUnicode("xn--" + String(decoding: encoded, as: UTF8.self))
        #expect(!result.hadError)
        #expect(Vectors.codePoints(result.domain) == Self.cjk)
    }

    @Test("NFC of a followed by 200,000 alternating U+0316 and U+0301", .timeLimit(.minutes(1)))
    func nfcLongNonStarterRun() {
        let input: [UInt32] = [0x61] + (0..<200_000).map { $0 % 2 == 0 ? 0x0316 : 0x0301 }
        let output = NFC.normalize(input)
        // Reordered by combining class, then the first U+0301 composes with the a: U+00E1, the
        // 100,000 U+0316 (ccc 220), and the other 99,999 U+0301 (ccc 230).
        let classes = output.dropFirst().map(NFC.combiningClass(of:))
        #expect(output.first == 0xE1)
        #expect(zip(classes, classes.dropFirst()).allSatisfy { $0 <= $1 }, "not sorted by combining class")
        #expect(output == [0xE1] + Array(repeating: 0x0316, count: 100_000) + Array(repeating: 0x0301, count: 99_999))
    }

    @Test("toASCII of 100,000 × U+0628 U+094D U+200C with checkJoiners", .timeLimit(.minutes(1)))
    func contextJLongLabel() throws {
        let input = String(repeating: "\u{0628}\u{094D}\u{200C}", count: 100_000)
        let result = try #require(TR46.toASCII(input, options: TR46.Options(checkJoiners: true)))
        // Each ZWNJ follows a virama, so the label is valid and encodes.
        #expect(result.hasPrefix("xn--"))
    }

    @Test("toASCII of a 1,000,000-character ASCII label", .timeLimit(.minutes(1)))
    func longASCIILabel() {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
        let input = (0..<1_000_000).map { alphabet[$0 % alphabet.count] }
        let lowered = input.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }
        let result = TR46.toASCII(String(decoding: input, as: UTF8.self))
        #expect(Vectors.bytes(result) == lowered)
    }

    @Test("toASCII and toUnicode of 200,000 labels \"a.\"", .timeLimit(.minutes(1)))
    func manyLabels() {
        let input = String(repeating: "a.", count: 200_000)
        #expect(Vectors.sameBytes(TR46.toASCII(input), input))
        let unicode = TR46.toUnicode(input)
        #expect(Vectors.sameBytes(unicode.domain, input) && !unicode.hadError)
    }
}
