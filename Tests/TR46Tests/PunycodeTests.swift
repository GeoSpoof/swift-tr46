import Testing

@testable import TR46

/// punycode.js 2.3.1's decode and encode, both implementations: RFC 3492's samples, the literal
/// and scalable paths against each other, and the JavaScript-specific rows (J1, J2, T8).
@Suite("Punycode: punycode.js 2.3.1, literal and scalable")
struct PunycodeTests {
    struct Sample: Sendable, CustomTestStringConvertible {
        let name: String
        let codePoints: [UInt32]
        /// The Punycode as RFC 3492 prints it, mixed-case annotation included.
        let rfc: String
        /// What punycode.js's encode gives: the same, except that its digits are always lower case.
        let encoded: String

        init(_ name: String, _ codePoints: [UInt32], rfc: String, encoded: String? = nil) {
            self.name = name
            self.codePoints = codePoints
            self.rfc = rfc
            self.encoded = encoded ?? rfc
        }

        var testDescription: String { "(\(name))" }
    }

    /// RFC 3492 section 7.1, (A) to (S), extracted from the RFC's text and checked against
    /// punycode.js 2.3.1 when this file was written.
    static let samples: [Sample] = [
            Sample(
                "A",
                [
                    0x0644, 0x064A, 0x0647, 0x0645, 0x0627, 0x0628, 0x062A, 0x0643, 0x0644, 0x0645,
                    0x0648, 0x0634, 0x0639, 0x0631, 0x0628, 0x064A, 0x061F,
                ],
                rfc: "egbpdaj6bu4bxfgehfvwxn"
            ),
            Sample(
                "B",
                [
                    0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D, 0x6587,
                ],
                rfc: "ihqwcrb4cv8a8dqg056pqjye"
            ),
            Sample(
                "C",
                [
                    0x4ED6, 0x5011, 0x7232, 0x4EC0, 0x9EBD, 0x4E0D, 0x8AAA, 0x4E2D, 0x6587,
                ],
                rfc: "ihqwctvzc91f659drss3x8bo0yb"
            ),
            Sample(
                "D",
                [
                    0x0050, 0x0072, 0x006F, 0x010D, 0x0070, 0x0072, 0x006F, 0x0073, 0x0074, 0x011B,
                    0x006E, 0x0065, 0x006D, 0x006C, 0x0075, 0x0076, 0x00ED, 0x010D, 0x0065, 0x0073,
                    0x006B, 0x0079,
                ],
                rfc: "Proprostnemluvesky-uyb24dma41a"
            ),
            Sample(
                "E",
                [
                    0x05DC, 0x05DE, 0x05D4, 0x05D4, 0x05DD, 0x05E4, 0x05E9, 0x05D5, 0x05D8, 0x05DC,
                    0x05D0, 0x05DE, 0x05D3, 0x05D1, 0x05E8, 0x05D9, 0x05DD, 0x05E2, 0x05D1, 0x05E8,
                    0x05D9, 0x05EA,
                ],
                rfc: "4dbcagdahymbxekheh6e0a7fei0b"
            ),
            Sample(
                "F",
                [
                    0x092F, 0x0939, 0x0932, 0x094B, 0x0917, 0x0939, 0x093F, 0x0928, 0x094D, 0x0926,
                    0x0940, 0x0915, 0x094D, 0x092F, 0x094B, 0x0902, 0x0928, 0x0939, 0x0940, 0x0902,
                    0x092C, 0x094B, 0x0932, 0x0938, 0x0915, 0x0924, 0x0947, 0x0939, 0x0948, 0x0902,
                ],
                rfc: "i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd"
            ),
            Sample(
                "G",
                [
                    0x306A, 0x305C, 0x307F, 0x3093, 0x306A, 0x65E5, 0x672C, 0x8A9E, 0x3092, 0x8A71,
                    0x3057, 0x3066, 0x304F, 0x308C, 0x306A, 0x3044, 0x306E, 0x304B,
                ],
                rfc: "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa"
            ),
            Sample(
                "H",
                [
                    0xC138, 0xACC4, 0xC758, 0xBAA8, 0xB4E0, 0xC0AC, 0xB78C, 0xB4E4, 0xC774, 0xD55C,
                    0xAD6D, 0xC5B4, 0xB97C, 0xC774, 0xD574, 0xD55C, 0xB2E4, 0xBA74, 0xC5BC, 0xB9C8,
                    0xB098, 0xC88B, 0xC744, 0xAE4C,
                ],
                rfc: "989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c"
            ),
            Sample(
                "I",
                [
                    0x043F, 0x043E, 0x0447, 0x0435, 0x043C, 0x0443, 0x0436, 0x0435, 0x043E, 0x043D,
                    0x0438, 0x043D, 0x0435, 0x0433, 0x043E, 0x0432, 0x043E, 0x0440, 0x044F, 0x0442,
                    0x043F, 0x043E, 0x0440, 0x0443, 0x0441, 0x0441, 0x043A, 0x0438,
                ],
                rfc: "b1abfaaepdrnnbgefbaDotcwatmq2g4l",
                encoded: "b1abfaaepdrnnbgefbadotcwatmq2g4l"
            ),
            Sample(
                "J",
                [
                    0x0050, 0x006F, 0x0072, 0x0071, 0x0075, 0x00E9, 0x006E, 0x006F, 0x0070, 0x0075,
                    0x0065, 0x0064, 0x0065, 0x006E, 0x0073, 0x0069, 0x006D, 0x0070, 0x006C, 0x0065,
                    0x006D, 0x0065, 0x006E, 0x0074, 0x0065, 0x0068, 0x0061, 0x0062, 0x006C, 0x0061,
                    0x0072, 0x0065, 0x006E, 0x0045, 0x0073, 0x0070, 0x0061, 0x00F1, 0x006F, 0x006C,
                ],
                rfc: "PorqunopuedensimplementehablarenEspaol-fmd56a"
            ),
            Sample(
                "K",
                [
                    0x0054, 0x1EA1, 0x0069, 0x0073, 0x0061, 0x006F, 0x0068, 0x1ECD, 0x006B, 0x0068,
                    0x00F4, 0x006E, 0x0067, 0x0074, 0x0068, 0x1EC3, 0x0063, 0x0068, 0x1EC9, 0x006E,
                    0x00F3, 0x0069, 0x0074, 0x0069, 0x1EBF, 0x006E, 0x0067, 0x0056, 0x0069, 0x1EC7,
                    0x0074,
                ],
                rfc: "TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g"
            ),
            Sample(
                "L",
                [
                    0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148, 0x751F,
                ],
                rfc: "3B-ww4c5e180e575a65lsy2b"
            ),
            Sample(
                "M",
                [
                    0x5B89, 0x5BA4, 0x5948, 0x7F8E, 0x6075, 0x002D, 0x0077, 0x0069, 0x0074, 0x0068,
                    0x002D, 0x0053, 0x0055, 0x0050, 0x0045, 0x0052, 0x002D, 0x004D, 0x004F, 0x004E,
                    0x004B, 0x0045, 0x0059, 0x0053,
                ],
                rfc: "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n"
            ),
            Sample(
                "N",
                [
                    0x0048, 0x0065, 0x006C, 0x006C, 0x006F, 0x002D, 0x0041, 0x006E, 0x006F, 0x0074,
                    0x0068, 0x0065, 0x0072, 0x002D, 0x0057, 0x0061, 0x0079, 0x002D, 0x305D, 0x308C,
                    0x305E, 0x308C, 0x306E, 0x5834, 0x6240,
                ],
                rfc: "Hello-Another-Way--fc4qua05auwb3674vfr0b"
            ),
            Sample(
                "O",
                [
                    0x3072, 0x3068, 0x3064, 0x5C4B, 0x6839, 0x306E, 0x4E0B, 0x0032,
                ],
                rfc: "2-u9tlzr9756bt3uc0v"
            ),
            Sample(
                "P",
                [
                    0x004D, 0x0061, 0x006A, 0x0069, 0x3067, 0x004B, 0x006F, 0x0069, 0x3059, 0x308B,
                    0x0035, 0x79D2, 0x524D,
                ],
                rfc: "MajiKoi5-783gue6qz075azm5e"
            ),
            Sample(
                "Q",
                [
                    0x30D1, 0x30D5, 0x30A3, 0x30FC, 0x0064, 0x0065, 0x30EB, 0x30F3, 0x30D0,
                ],
                rfc: "de-jg4avhby1noc0d"
            ),
            Sample(
                "R",
                [
                    0x305D, 0x306E, 0x30B9, 0x30D4, 0x30FC, 0x30C9, 0x3067,
                ],
                rfc: "d9juau41awczczp"
            ),
            Sample(
                "S",
                [
                    0x002D, 0x003E, 0x0020, 0x0024, 0x0031, 0x002E, 0x0030, 0x0030, 0x0020, 0x003C,
                    0x002D,
                ],
                rfc: "-> $1.00 <--"
            ),
    ]

    static let strategies: [Punycode.Strategy] = [.literal, .scalable, .automatic]

    @Test("RFC 3492 section 7.1 samples decode and encode with every strategy", arguments: samples)
    func rfcSample(_ sample: Sample) {
        for strategy in Self.strategies {
            #expect(Punycode.decode(Vectors.codePoints(sample.rfc), strategy: strategy) == sample.codePoints, "\(strategy) decode")
            #expect(Punycode.encode(sample.codePoints, strategy: strategy) == Array(sample.encoded.utf8), "\(strategy) encode")
        }
    }

    /// The raw values punycode.js's decode produces before `String.fromCodePoint`, and what tr46
    /// then iterates (J1, J2).
    @Test("J1 and J2: decoded surrogate values re-pair, and a value above U+10FFFF is a RangeError")
    func fromCodePoint() {
        let rows: [(digits: String, raw: [UInt32], codePoints: [UInt32]?)] = [
            ("8c9bk9h", [0xD83D, 0xDE00], [0x1F600]),
            ("8c9b", [0xD83D], [0xD83D]),
            ("8c9bj9h", [0xDE00, 0xD83D], [0xDE00, 0xD83D]),
            ("a-8f4gp1m", [0x61, 0xD83D, 0xDE00], [0x61, 0x1F600]),
            ("en32g", [0x110000], nil),
        ]
        for row in rows {
            for strategy in Self.strategies {
                let raw = Punycode.decode(Vectors.codePoints(row.digits), strategy: strategy)
                #expect(raw == row.raw, "\(row.digits), \(strategy)")
                #expect(raw.flatMap(JSString.fromCodePoints) == row.codePoints, "\(row.digits), \(strategy)")
            }
        }
        // The same rows through toASCII (J1 and J2 in BehaviourFromJavaScript.md).
        let domains: [(String, String?)] = [
            ("xn--8c9bk9h.com", "xn--e28h.com"),
            ("xn--8c9b.com", nil),
            ("xn--8c9bj9h.com", nil),
            ("xn--a-8f4gp1m.com", "xn--a-jv3s.com"),
            ("xn--en32g.com", nil),
        ]
        for (input, expected) in domains {
            #expect(Vectors.sameBytes(TR46.toASCII(input), expected), "\(input)")
        }
    }

    /// T8: with 10,950 basic code points before it, U+30000 overflows `delta` in punycode.js's
    /// encode; with 10,900 it doesn't.
    @Test("T8: an encode overflow fails only toASCII")
    func encodeOverflow() {
        let over = [UInt32](repeating: 0x61, count: 10_950) + [0x30000]
        let under = [UInt32](repeating: 0x61, count: 10_900) + [0x30000]
        for strategy in Self.strategies {
            #expect(Punycode.encode(over, strategy: strategy) == nil, "\(strategy)")
            #expect(Punycode.encode(under, strategy: strategy) != nil, "\(strategy)")
        }
        #expect(Punycode.encode(under, strategy: .literal) == Punycode.encode(under, strategy: .scalable))

        let overDomain = String(repeating: "a", count: 10_950) + "\u{30000}"
        let underDomain = String(repeating: "a", count: 10_900) + "\u{30000}"
        #expect(TR46.toASCII(overDomain) == nil)
        #expect(TR46.toUnicode(overDomain).hadError == false)
        #expect(TR46.toASCII(underDomain)?.utf8.count == 10_913)
    }

    // MARK: - Literal against scalable

    /// One drawn input: code points to encode, and digits to decode.
    struct Case: Sendable {
        let codePoints: [UInt32]
        let digits: [UInt32]
    }

    /// A length from 1 to 3,000, roughly log-uniform, so short inputs are common and long ones
    /// still appear: the literal path is O(n²), and every one of these runs through it.
    private static func length(_ generator: inout SeededGenerator) -> Int {
        let ceiling = min(3_000, 1 << Int.random(in: 0...12, using: &generator))
        return Int.random(in: 1...ceiling, using: &generator)
    }

    private static func codePoint(_ generator: inout SeededGenerator) -> UInt32 {
        switch UInt32.random(in: 0..<100, using: &generator) {
        case 0..<30: return UInt32.random(in: 0..<0x80, using: &generator)          // basic
        case 30..<55: return UInt32.random(in: 0x80..<0xD800, using: &generator)    // BMP
        case 55..<65: return UInt32.random(in: 0xD800...0xDFFF, using: &generator)  // surrogate values
        case 65..<85: return UInt32.random(in: 0x10000...0x10FFFF, using: &generator)
        case 85..<90: return 0x10FFFF
        default: return UInt32.random(in: 0xE000...0xFFFF, using: &generator)
        }
    }

    /// Code points of six shapes: anything, a few values repeated, mostly basic with a few large
    /// values, runs of one value, sorted values, and the overflow edge.
    ///
    /// Encode overflows when `(m - n) * (handled + 1)` passes 2^31 - 1, and m is at most 0x10FFFF,
    /// so it needs about 1,950 handled code points. The last shape is 2,000 to 2,997 basic code
    /// points and up to three copies of one value within 2,000 of the threshold for that count, so
    /// about half overflow.
    private static func codePoints(_ generator: inout SeededGenerator) -> [UInt32] {
        if UInt32.random(in: 0..<6, using: &generator) == 0 {
            let basic = Int.random(in: 2_000...2_997, using: &generator)
            let threshold = 2_147_483_647 / (basic + 1) + 128
            let value = UInt32(threshold + Int.random(in: -2_000...2_000, using: &generator))
            var result = (0..<basic).map { _ in UInt32.random(in: 0x61...0x7A, using: &generator) }
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                result.insert(value, at: Int.random(in: 0...result.count, using: &generator))
            }
            return result
        }
        let count = length(&generator)
        switch UInt32.random(in: 0..<5, using: &generator) {
        case 0:
            return (0..<count).map { _ in codePoint(&generator) }
        case 1:
            let palette = (0..<Int.random(in: 1...8, using: &generator)).map { _ in codePoint(&generator) }
            return (0..<count).map { _ in palette.randomElement(using: &generator)! }
        case 2:
            return (0..<count).map { _ in
                UInt32.random(in: 0..<100, using: &generator) < 97
                    ? UInt32.random(in: 0x61...0x7A, using: &generator)
                    : UInt32.random(in: 0x30000...0x10FFFF, using: &generator)
            }
        case 3:
            var result: [UInt32] = []
            while result.count < count {
                let value = codePoint(&generator)
                result += [UInt32](repeating: value, count: min(count - result.count, Int.random(in: 1...50, using: &generator)))
            }
            return result
        default:
            return (0..<count).map { _ in codePoint(&generator) }.sorted()
        }
    }

    /// Decoder input: random digits, sometimes after a basic prefix and a delimiter, sometimes in
    /// upper case or with a character that isn't a digit, or a long run of one digit, which
    /// overflows.
    private static func digits(_ generator: inout SeededGenerator) -> [UInt32] {
        let count = length(&generator)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789".unicodeScalars.map(\.value))
        var result: [UInt32] = []
        if Bool.random(using: &generator) {
            result = (0..<Int.random(in: 0...20, using: &generator)).map { _ in UInt32.random(in: 0x20..<0x80, using: &generator) }
            result.append(0x2D)
        }
        switch UInt32.random(in: 0..<10, using: &generator) {
        case 0:
            result += [UInt32](repeating: [0x39, 0x7A, 0x61].randomElement(using: &generator)!, count: count)
        case 1:
            // Upper-case letters, which basicToDigit reads like lower-case ones.
            result += (0..<count).map { _ in
                let digit = alphabet.randomElement(using: &generator)!
                return digit >= 0x61 ? digit - 0x20 : digit
            }
        case 2:
            result += (0..<count).map { _ in alphabet.randomElement(using: &generator)! }
            result[Int.random(in: 0..<result.count, using: &generator)] = [0x21, 0xE9, 0x1F600].randomElement(using: &generator)!
        default:
            result += (0..<count).map { _ in alphabet.randomElement(using: &generator)! }
        }
        return result
    }

    static func cases(_ count: Int) -> [Case] {
        (0..<count).map { index in
            var generator = SeededGenerator(seed: 0x7472_3436 &+ UInt64(index) &* 0x9E37_79B9)
            return Case(codePoints: codePoints(&generator), digits: digits(&generator))
        }
    }

    struct Outcome: Sendable {
        var failures: [String] = []
        var encoded = 0
        var encodeOverflows = 0
        var decoded = 0
        var decodeFailures = 0
        var longest = 0
    }

    @Test("literal and scalable agree on 2,000 drawn inputs of 1 to 3,000 code points")
    func literalEqualsScalable() async {
        let cases = Self.cases(2_000)
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            let shards = 16
            for shard in 0..<shards {
                group.addTask {
                    var outcome = Outcome()
                    for index in stride(from: shard, to: cases.count, by: shards) {
                        let item = cases[index]
                        outcome.longest = max(outcome.longest, item.codePoints.count, item.digits.count)
                        let literal = Punycode.encode(item.codePoints, strategy: .literal)
                        let scalable = Punycode.encode(item.codePoints, strategy: .scalable)
                        if literal != scalable {
                            outcome.failures.append("case \(index): encode of \(item.codePoints.count) code points differs")
                        }
                        if let literal {
                            outcome.encoded += 1
                            let digits = literal.map { UInt32($0) }
                            let back = Punycode.decode(digits, strategy: .literal)
                            if back != Punycode.decode(digits, strategy: .scalable) {
                                outcome.failures.append("case \(index): decode of the encoding differs")
                            }
                            if back != item.codePoints {
                                outcome.failures.append("case \(index): decode(encode(x)) != x")
                            }
                        } else {
                            outcome.encodeOverflows += 1
                        }
                        let decoded = Punycode.decode(item.digits, strategy: .literal)
                        if decoded != Punycode.decode(item.digits, strategy: .scalable) {
                            outcome.failures.append("case \(index): decode of \(item.digits.count) digits differs")
                        }
                        if decoded == nil { outcome.decodeFailures += 1 } else { outcome.decoded += 1 }
                    }
                    return outcome
                }
            }
            var total = Outcome()
            for await part in group {
                total.failures += part.failures
                total.encoded += part.encoded
                total.encodeOverflows += part.encodeOverflows
                total.decoded += part.decoded
                total.decodeFailures += part.decodeFailures
                total.longest = max(total.longest, part.longest)
            }
            return total
        }
        #expect(outcome.failures.isEmpty, "\(outcome.failures.count) differences:\n\(outcome.failures.prefix(20).joined(separator: "\n"))")
        print(
            "[punycode] literal vs scalable, \(cases.count) cases up to \(outcome.longest) code points: "
                + "encode \(outcome.encoded) ok + \(outcome.encodeOverflows) overflow; "
                + "decode \(outcome.decoded) ok + \(outcome.decodeFailures) error; \(outcome.failures.count) differences"
        )
        // The draw has to reach both outcomes of both functions, and long inputs, to mean anything.
        #expect(outcome.encoded > 200 && outcome.encodeOverflows > 100, "encoded \(outcome.encoded), overflowed \(outcome.encodeOverflows)")
        #expect(outcome.decoded > 100 && outcome.decodeFailures > 200, "decoded \(outcome.decoded), failed \(outcome.decodeFailures)")
        #expect(outcome.longest > 2_500)
    }
}
