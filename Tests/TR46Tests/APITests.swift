import Testing

@testable import TR46

/// The public API: its defaults and versions, tr46's own small test files, and the named
/// behaviours of plan.md §6 that come from tr46 and JavaScript.
@Suite("API: TR46.toASCII and TR46.toUnicode")
struct APITests {
    private static func expectASCII(
        _ input: String,
        _ options: TR46.Options = TR46.Options(),
        _ expected: String?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = TR46.toASCII(input, options: options)
        #expect(
            Vectors.sameBytes(actual, expected),
            "toASCII(\(Vectors.escaped(input))) = \(Vectors.escaped(actual)), expected \(Vectors.escaped(expected))",
            sourceLocation: sourceLocation
        )
    }

    private static func expectUnicode(
        _ input: String,
        _ options: TR46.Options = TR46.Options(),
        _ domain: String,
        _ hadError: Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = TR46.toUnicode(input, options: options)
        let actualText = "(\(Vectors.escaped(actual.domain)), \(actual.hadError))"
        let expectedText = "(\(Vectors.escaped(domain)), \(hadError))"
        #expect(
            Vectors.sameBytes(actual.domain, domain) && actual.hadError == hadError,
            "toUnicode(\(Vectors.escaped(input))) = \(actualText), expected \(expectedText)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Shape

    @Test("the options default to tr46's: every check off, bundled NFC")
    func defaults() {
        let options = TR46.Options()
        #expect(!options.checkHyphens)
        #expect(!options.checkBidi)
        #expect(!options.checkJoiners)
        #expect(!options.useSTD3ASCIIRules)
        #expect(!options.transitionalProcessing)
        #expect(!options.verifyDNSLength)
        #expect(!options.ignoreInvalidPunycode)
        #expect(options.normalization == .bundled)
        #expect(options == TR46.Options(
            checkHyphens: false, checkBidi: false, checkJoiners: false, useSTD3ASCIIRules: false,
            transitionalProcessing: false, verifyDNSLength: false, ignoreInvalidPunycode: false,
            normalization: .bundled
        ))
        #expect(options == OptionCombinations.options(0))
    }

    @Test("the versions are tr46 7.0.0 and Unicode 18.0.0")
    func versions() {
        #expect(TR46.upstreamVersion == "7.0.0")
        #expect(TR46.unicodeVersion == "18.0.0")
    }

    private static func requireSendableHashable<T: Sendable & Hashable>(_: T.Type) {}

    @Test("Options and Normalization are Sendable and Hashable")
    func sendableHashable() {
        Self.requireSendableHashable(TR46.Options.self)
        Self.requireSendableHashable(TR46.Normalization.self)
        // All 128 combinations are distinct values.
        #expect(Set(OptionCombinations.all).count == 128)
        #if canImport(Darwin)
        let foundation = TR46.Options(normalization: .foundation)
        #expect(foundation != TR46.Options())
        #expect(Set(OptionCombinations.all + [foundation]).count == 129)
        #endif
    }

    @Test("the examples in the documentation")
    func documentedExamples() {
        Self.expectASCII("münchen.de", TR46.Options(checkBidi: true, checkJoiners: true), "xn--mnchen-3ya.de")
        Self.expectASCII("Bücher.example", TR46.Options(), "xn--bcher-kva.example")
        Self.expectASCII("xn--zz.com", TR46.Options(), nil)
        Self.expectASCII("faß.de", TR46.Options(transitionalProcessing: true), "fass.de")
        Self.expectUnicode("xn--mnchen-3ya.de", TR46.Options(), "münchen.de", false)
        Self.expectUnicode("xn--zz.xn--mnchen-3ya.de", TR46.Options(), "xn--zz.münchen.de", true)
    }

    // MARK: - tr46's test files

    /// tr46 v7.0.0 test/std3ASCIIRules.js, case for case.
    @Test("tr46's std3ASCIIRules.js")
    func std3ASCIIRules() {
        let options = TR46.Options(checkHyphens: false, checkBidi: false, checkJoiners: false, useSTD3ASCIIRules: true, verifyDNSLength: false)
        var cases: [(input: String, output: String?)] = []
        // Add test cases for valid characters
        let allowedChars = Array("abcdefghijklmnopqrstuvwxyz" + "0123456789" + "-")
        for char in allowedChars {
            cases.append((String(char), String(char)))
        }
        // Add not supported ascii characters
        for i in UInt8(0)..<128 {
            let char = Character(Unicode.Scalar(i))
            if allowedChars.contains(char) {
                continue
            }
            // Upper-case letters are converted to lower case, so we we exclude them from a negative test case
            if (0x41...0x5A).contains(i) {
                continue
            }
            // Dot is exclude from negative test cases, since it is allowed in domain names
            if char == "." {
                continue
            }
            cases.append((String(char), nil))
        }
        // Add a unicode character, since it should be converted to punycode
        cases.append(("é", "xn--9ca"))
        // Additional test cases, with mixed valid and invalid characters
        cases.append(("inv@alid", nil))
        cases.append(("valid", "valid"))
        cases.append(("unicodé", "xn--unicod-gva"))
        cases.append(("uni!codé", nil))

        #expect(cases.count == 106)
        for (input, output) in cases {
            Self.expectASCII(input, options, output)
        }
    }

    /// tr46 v7.0.0 test/url-host-parsing.js: every code point 0x00–0x7E alone.
    @Test("tr46's url-host-parsing.js")
    func urlHostParsing() {
        let options = TR46.Options(useSTD3ASCIIRules: false)
        for i in UInt8(0)..<0x7F {
            let string = String(Character(Unicode.Scalar(i)))
            let lowered = String(Character(Unicode.Scalar((0x41...0x5A).contains(i) ? i + 0x20 : i)))
            Self.expectASCII(string, options, lowered)
            Self.expectUnicode(string, options, lowered, false)
        }
    }

    // MARK: - Behaviour from JavaScript and tr46 (plan.md §6)

    @Test("J3: a decoded lone surrogate comes back as U+FFFD, with an error")
    func loneSurrogateBecomesReplacementCharacter() {
        Self.expectUnicode("xn--8c9b.com", TR46.Options(), "\u{FFFD}.com", true)
        Self.expectUnicode("xn--8c9bj9h.com", TR46.Options(), "\u{FFFD}\u{FFFD}.com", true)
        Self.expectUnicode("xn--8c9bk9h.com", TR46.Options(), "\u{1F600}.com", false)
    }

    @Test("J5: CheckHyphens counts positions 3 and 4 in code points")
    func checkHyphensCountsCodePoints() {
        Self.expectASCII("😀b--c", TR46.Options(checkHyphens: true), nil)
        Self.expectASCII("ab😀--c", TR46.Options(checkHyphens: true), "xn--ab--c-0224d")
        Self.expectASCII("😀b--c", TR46.Options(), "xn--b--c-u973c")
    }

    @Test("T1: the error is sticky, and later labels are still decoded")
    func errorIsSticky() {
        Self.expectUnicode("xn--zz.xn--mnchen-3ya.de", TR46.Options(), "xn--zz.münchen.de", true)
        Self.expectASCII("xn--zz.xn--mnchen-3ya.de", TR46.Options(), nil)
    }

    @Test("T6: transitional processing maps ẞ to ss, and only then")
    func capitalSharpS() {
        Self.expectASCII("ẞ.de", TR46.Options(transitionalProcessing: true), "ss.de")
        Self.expectASCII("ẞ.de", TR46.Options(), "xn--zca.de")
        Self.expectASCII("faß.de", TR46.Options(transitionalProcessing: true), "fass.de")
        Self.expectASCII("faß.de", TR46.Options(), "xn--fa-hia.de")
    }

    @Test("T7: an earlier ZWNJ that a virama allowed satisfies a later ZWNJ's context")
    func contextJEarlierZWNJ() {
        Self.expectASCII("\u{0628}\u{094D}\u{200C}\u{0628}\u{200C}a", TR46.Options(checkJoiners: true), "xn--a-0mca333a472bba")
        Self.expectASCII("\u{0628}\u{200C}a", TR46.Options(checkJoiners: true), nil)
    }

    @Test("T9: verifyDNSLength's edges, and an empty result without it")
    func dnsLength() {
        let verify = TR46.Options(verifyDNSLength: true)
        let a = { (count: Int) in String(repeating: "a", count: count) }
        Self.expectASCII(a(63), verify, a(63))
        Self.expectASCII(a(64), verify, nil)
        Self.expectASCII(a(64), TR46.Options(), a(64))
        let total253 = [a(63), a(63), a(63), a(61)].joined(separator: ".")
        let total254 = [a(63), a(63), a(63), a(62)].joined(separator: ".")
        Self.expectASCII(total253, verify, total253)
        Self.expectASCII(total254, verify, nil)
        Self.expectASCII(total253 + ".", verify, nil)
        // The A-label is what is measured: 63 and 64 bytes.
        Self.expectASCII("ü" + a(55), verify, "xn--" + a(55) + "-oxf")
        Self.expectASCII("ü" + a(56), verify, nil)
        Self.expectASCII("", verify, nil)
        Self.expectASCII("example.com.", verify, nil)
        Self.expectASCII("a..b", verify, nil)
        // Without it, an empty result is "", not nil, and empty labels stay (J9).
        Self.expectASCII("", TR46.Options(), "")
        Self.expectASCII("\u{00AD}", TR46.Options(), "")
        Self.expectASCII("example.com.", TR46.Options(), "example.com.")
        Self.expectASCII("a..b", TR46.Options(), "a..b")
        Self.expectASCII(".", TR46.Options(), ".")
    }

    /// The options each invariance test runs under: tr46's defaults, and the two option sets the
    /// conformance files use.
    private static let invarianceOptions: [TR46.Options] = [
        TR46.Options(),
        TR46.Options(checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true, verifyDNSLength: true),
        TR46.Options(checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true, transitionalProcessing: true, verifyDNSLength: true),
        TR46.Options(checkBidi: true, checkJoiners: true),
    ]

    private static func conformanceInputs() throws -> [String] {
        let wpt = try IDNAVectors.wpt()
        return try IDNAVectors.idnaTestV2().vectors.map(\.source) + (wpt.toascii + wpt.idnaTestV2).map(\.input)
    }

    @Test("T3: ignoreInvalidPunycode changes no result")
    func ignoreInvalidPunycodeChangesNothing() throws {
        let inputs = try Self.conformanceInputs()
        #expect(inputs.count == 6_394 + 61 + 1_680)
        var failures: [String] = []
        for input in inputs {
            for var options in Self.invarianceOptions {
                options.ignoreInvalidPunycode = false
                let ascii = TR46.toASCII(input, options: options)
                let unicode = TR46.toUnicode(input, options: options)
                options.ignoreInvalidPunycode = true
                let asciiIgnoring = TR46.toASCII(input, options: options)
                let unicodeIgnoring = TR46.toUnicode(input, options: options)
                if !Vectors.sameBytes(ascii, asciiIgnoring)
                    || !Vectors.sameBytes(unicode.domain, unicodeIgnoring.domain)
                    || unicode.hadError != unicodeIgnoring.hadError {
                    failures.append(Vectors.escaped(input))
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) differ:\n\(failures.prefix(20).joined(separator: "\n"))")
    }

    @Test("toUnicode ignores verifyDNSLength")
    func toUnicodeIgnoresVerifyDNSLength() throws {
        var failures: [String] = []
        for input in try Self.conformanceInputs() {
            for var options in Self.invarianceOptions {
                options.verifyDNSLength = false
                let off = TR46.toUnicode(input, options: options)
                options.verifyDNSLength = true
                let on = TR46.toUnicode(input, options: options)
                if !Vectors.sameBytes(off.domain, on.domain) || off.hadError != on.hadError {
                    failures.append(Vectors.escaped(input))
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) differ:\n\(failures.prefix(20).joined(separator: "\n"))")
    }

    @Test("an empty domain is one empty label")
    func emptyDomain() {
        let result = Processing.process("", options: TR46.Options())
        #expect(result.labels == [[]])
        #expect(result.error == false)
        #expect(Processing.process("a.", options: TR46.Options()).labels == [[0x61], []])
    }
}
