import Testing

@testable import TR46

/// `Resources/differential.json`: real tr46 7.0.0's answers under pinned Node, for the IdnaTestV2
/// sources, the WPT inputs, the curated inputs and the fuzz inputs, under all 128 toASCII and all 64
/// toUnicode option combinations. Every answer must be reproduced byte for byte, and toUnicode's
/// error flag with it.
@Suite("Differential: real tr46 7.0.0 under every option combination")
struct DifferentialTests {
    // MARK: - differential.json

    /// Which option combinations give an answer: bit k set for combination k, from fixed-width hex.
    struct Mask: Sendable {
        let low: UInt64
        let high: UInt64

        init(hex: String, combinations: Int) throws {
            guard hex.utf8.count == combinations / 4, hex.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
                throw Vectors.LoadError(description: "\"\(hex)\" is not a mask of \(combinations / 4) hex digits")
            }
            let digits = Array(hex.utf8)
            let split = max(0, digits.count - 16)
            low = UInt64(String(decoding: digits[split...], as: UTF8.self), radix: 16)!
            high = split == 0 ? 0 : UInt64(String(decoding: digits[..<split], as: UTF8.self), radix: 16)!
        }

        func contains(_ k: Int) -> Bool {
            k < 64 ? low & (1 << UInt64(k)) != 0 : high & (1 << UInt64(k - 64)) != 0
        }
    }

    /// `[answer or null, mask]`
    struct ASCIIAnswer: Decodable, Sendable {
        let value: String?
        let mask: Mask

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            value = try row.decodeNil() ? nil : row.decode(String.self)
            mask = try Mask(hex: row.decode(String.self), combinations: 128)
            guard row.isAtEnd else {
                throw Vectors.LoadError(description: "a toASCII answer with more than two elements")
            }
        }
    }

    /// `[domain, error, mask, replacedLoneSurrogates?]`
    struct UnicodeAnswer: Decodable, Sendable {
        let domain: String
        let hadError: Bool
        let mask: Mask
        /// tr46's domain held a lone surrogate, which `domain` has as U+FFFD (J3).
        let replacedLoneSurrogates: Bool

        init(from decoder: any Decoder) throws {
            var row = try decoder.unkeyedContainer()
            domain = try row.decode(String.self)
            hadError = try row.decode(Bool.self)
            mask = try Mask(hex: row.decode(String.self), combinations: 64)
            // Written only as true, and tr46 gives a lone surrogate only with an error.
            replacedLoneSurrogates = row.isAtEnd ? false : try row.decode(Bool.self)
            guard row.isAtEnd, row.count == 3 || replacedLoneSurrogates, !replacedLoneSurrogates || hadError else {
                throw Vectors.LoadError(description: "a malformed toUnicode answer for \(Vectors.escaped(domain))")
            }
        }
    }

    struct Vector: Decodable, Sendable {
        let input: String
        let toASCII: [ASCIIAnswer]
        let toUnicode: [UnicodeAnswer]
        /// Present only when a code point the vector passes through is newer than Unicode 14.0.
        let age: String?
    }

    struct Package: Decodable, Sendable {
        let version: String
        let integrity: String
    }

    struct Node: Decodable, Sendable {
        let version: String
        let unicode: String
        let icu: String
    }

    struct OptionOrder: Decodable, Sendable {
        let toASCII: [String]
        let toUnicode: [String]
    }

    struct Counts: Decodable, Sendable {
        let inputs: Int
        let idnaTestV2: Int
        let wpt: Int
        let curated: Int
        let fuzz: Int
        let excludedNewerThanNode: Int
        let toASCIIResults: Int
        let toUnicodeResults: Int
    }

    struct File: Decodable, Sendable {
        let tr46: Package
        let punycode: Package
        let node: Node
        let fuzzSeed: String
        let optionOrder: OptionOrder
        let counts: Counts
        let vectors: [Vector]
    }

    /// The file, after checking its header against its vectors and against this package.
    static func load() throws -> File {
        let file = try Vectors.load(File.self, from: "differential")
        try #require(file.tr46.version == TR46.upstreamVersion, "differential.json is tr46 \(file.tr46.version)'s")
        try #require(file.optionOrder.toASCII == OptionCombinations.names)
        try #require(file.optionOrder.toUnicode == OptionCombinations.names.filter { $0 != "verifyDNSLength" })
        let counts = file.counts
        try #require(counts.inputs == file.vectors.count, "counts.inputs is \(counts.inputs), the file has \(file.vectors.count)")
        try #require(counts.idnaTestV2 + counts.wpt + counts.curated + counts.fuzz == counts.inputs, "\(counts)")
        try #require(counts.toASCIIResults == counts.inputs * 128, "\(counts)")
        try #require(counts.toUnicodeResults == counts.inputs * 64, "\(counts)")
        return file
    }

    /// Which answer each combination has: index k holds the answer index for combination k, or
    /// nil if the masks don't partition the combinations.
    static func partition(_ masks: [Mask], combinations: Int) -> [Int]? {
        var owner = [Int?](repeating: nil, count: combinations)
        for (index, mask) in masks.enumerated() {
            for k in 0..<combinations where mask.contains(k) {
                if owner[k] != nil { return nil }
                owner[k] = index
            }
        }
        let owners = owner.compactMap { $0 }
        return owners.count == combinations ? owners : nil
    }

    /// toUnicode's combination `k` of 64, in the file's toUnicode order: `TR46.Options`'s order
    /// without verifyDNSLength, which toUnicode ignores and is passed separately.
    static func toUnicodeOptions(
        _ k: Int,
        verifyDNSLength: Bool = false,
        normalization: TR46.Normalization = .bundled
    ) -> TR46.Options {
        TR46.Options(
            checkHyphens: k & 1 != 0,
            checkBidi: k & 2 != 0,
            checkJoiners: k & 4 != 0,
            useSTD3ASCIIRules: k & 8 != 0,
            transitionalProcessing: k & 16 != 0,
            verifyDNSLength: verifyDNSLength,
            ignoreInvalidPunycode: k & 32 != 0,
            normalization: normalization
        )
    }

    static func describeToUnicode(_ k: Int) -> String {
        let names = OptionCombinations.names.filter { $0 != "verifyDNSLength" }
        let on = names.indices.filter { k & (1 << $0) != 0 }.map { names[$0] }
        return on.isEmpty ? "no options" : on.joined(separator: ", ")
    }

    // MARK: - Running

    struct Tally: Sendable {
        var toASCIIPassed = 0
        var toASCIITotal = 0
        var toUnicodePassed = 0
        var toUnicodeTotal = 0
        var failureCount = 0
        var failures: [String] = []

        mutating func fail(_ message: String) {
            failureCount += 1
            if failures.count < 20 { failures.append(message) }
        }

        mutating func add(_ other: Tally) {
            toASCIIPassed += other.toASCIIPassed
            toASCIITotal += other.toASCIITotal
            toUnicodePassed += other.toUnicodePassed
            toUnicodeTotal += other.toUnicodeTotal
            failureCount += other.failureCount
            failures += other.failures.prefix(20 - min(20, failures.count))
        }
    }

    /// Every combination of one vector, with the bundled NFC.
    static func check(_ vector: Vector, into tally: inout Tally) {
        let input = vector.input
        guard let asciiOwners = partition(vector.toASCII.map(\.mask), combinations: 128),
              let unicodeOwners = partition(vector.toUnicode.map(\.mask), combinations: 64) else {
            tally.fail("\(Vectors.escaped(input)): the masks don't partition the combinations")
            return
        }

        let asciiExpected = vector.toASCII.map { Vectors.bytes($0.value) }
        for k in 0..<128 {
            tally.toASCIITotal += 1
            let actual = TR46.toASCII(input, options: OptionCombinations.options(k))
            let expected = asciiExpected[asciiOwners[k]]
            if Vectors.bytes(actual) == expected {
                tally.toASCIIPassed += 1
            } else {
                tally.fail("toASCII(\(Vectors.escaped(input))) with \(OptionCombinations.describe(k)) = \(Vectors.escaped(actual)), "
                    + "tr46 gives \(Vectors.escaped(vector.toASCII[asciiOwners[k]].value))")
            }
        }

        let unicodeExpected = vector.toUnicode.map { Array($0.domain.utf8) }
        for k in 0..<64 {
            tally.toUnicodeTotal += 1
            let answer = vector.toUnicode[unicodeOwners[k]]
            let expected = unicodeExpected[unicodeOwners[k]]
            let actual = TR46.toUnicode(input, options: toUnicodeOptions(k))
            if Array(actual.domain.utf8) == expected && actual.hadError == answer.hadError {
                tally.toUnicodePassed += 1
            } else {
                tally.fail("toUnicode(\(Vectors.escaped(input))) with \(describeToUnicode(k)) = "
                    + "(\(Vectors.escaped(actual.domain)), \(actual.hadError)), tr46 gives (\(Vectors.escaped(answer.domain)), \(answer.hadError))")
            }
            // tr46's toUnicode has no verifyDNSLength, so turning it on must change nothing.
            let verifying = TR46.toUnicode(input, options: toUnicodeOptions(k, verifyDNSLength: true))
            if Array(verifying.domain.utf8) != Array(actual.domain.utf8) || verifying.hadError != actual.hadError {
                tally.fail("toUnicode(\(Vectors.escaped(input))) with \(describeToUnicode(k)) changes with verifyDNSLength: "
                    + "(\(Vectors.escaped(verifying.domain)), \(verifying.hadError)) against (\(Vectors.escaped(actual.domain)), \(actual.hadError))")
            }
        }
    }

    @Test("every input under all 128 toASCII and 64 toUnicode combinations, with the bundled NFC")
    func bundled() async throws {
        let file = try Self.load()
        let vectors = file.vectors
        let shards = 32
        let tally = await withTaskGroup(of: Tally.self) { group in
            for shard in 0..<shards {
                group.addTask {
                    var tally = Tally()
                    for index in stride(from: shard, to: vectors.count, by: shards) {
                        Self.check(vectors[index], into: &tally)
                    }
                    return tally
                }
            }
            var total = Tally()
            for await part in group { total.add(part) }
            return total
        }

        print(
            "[differential] tr46 \(file.tr46.version) / Node \(file.node.version): \(vectors.count) inputs; "
                + "toASCII \(tally.toASCIIPassed)/\(tally.toASCIITotal); toUnicode \(tally.toUnicodePassed)/\(tally.toUnicodeTotal)"
        )
        #expect(tally.toASCIITotal == file.counts.toASCIIResults)
        #expect(tally.toUnicodeTotal == file.counts.toUnicodeResults)
        #expect(tally.failureCount == 0, "\(tally.failureCount) failures, the first \(tally.failures.count):\n\(tally.failures.joined(separator: "\n"))")
    }

    #if canImport(Darwin)
    /// The combinations the `.foundation` comparison runs: tr46's defaults, GeoSpoof's
    /// (checkBidi and checkJoiners), and every check on, nontransitional and transitional
    /// (with verifyDNSLength for toASCII, as IdnaTestV2's harness has it).
    static let foundationCombinations: [(name: String, toASCII: Int, toUnicode: Int)] = [
        ("default", 0, 0),
        ("GeoSpoof", 2 | 4, 2 | 4),
        ("strict", 1 | 2 | 4 | 8 | 32, 1 | 2 | 4 | 8),
        ("strict, transitional", 1 | 2 | 4 | 8 | 16 | 32, 1 | 2 | 4 | 8 | 16),
    ]

    /// The first string tr46's flow normalizes, or checks is normalized, on which Foundation's NFC
    /// and the bundled NFC disagree: the mapped domain, a label of its NFC, or a decoded label.
    /// nil if they agree on all of them, so the difference isn't Foundation's NFC.
    static func foundationNFCDefect(_ input: String) -> (codePoints: [UInt32], foundation: [UInt32], bundled: [UInt32])? {
        for transitional in [false, true] {
            let mapped = Processing.mapChars(input, transitionalProcessing: transitional)
            var candidates = [mapped]
            for label in NFC.normalize(mapped).split(separator: 0x2E, omittingEmptySubsequences: false).map(Array.init) {
                candidates.append(label)
                if Processing.hasACEPrefix(label),
                   let decoded = Punycode.decode(Array(label.dropFirst(4))).flatMap(JSString.fromCodePoints),
                   !decoded.contains(where: { (0xD800...0xDFFF).contains($0) }) {
                    candidates.append(decoded)
                }
            }
            for candidate in candidates {
                let foundation = FoundationNFC.normalize(candidate)
                let bundled = NFC.normalize(candidate)
                if foundation != bundled { return (candidate, foundation, bundled) }
            }
        }
        return nil
    }

    @Test("every input without an age under the default, GeoSpoof and strict combinations, with Foundation's NFC")
    func foundation() throws {
        let file = try Self.load()
        let vectors = file.vectors.filter { $0.age == nil }
        var compared = 0
        var failures: [String] = []
        var knownDefects: [String] = []
        for vector in vectors {
            guard let asciiOwners = Self.partition(vector.toASCII.map(\.mask), combinations: 128),
                  let unicodeOwners = Self.partition(vector.toUnicode.map(\.mask), combinations: 64) else {
                failures.append("\(Vectors.escaped(vector.input)): the masks don't partition the combinations")
                continue
            }
            var problems: [String] = []
            for combination in Self.foundationCombinations {
                compared += 1
                var asciiOptions = OptionCombinations.options(combination.toASCII)
                asciiOptions.normalization = .foundation
                let ascii = TR46.toASCII(vector.input, options: asciiOptions)
                let expectedASCII = vector.toASCII[asciiOwners[combination.toASCII]].value
                if !Vectors.sameBytes(ascii, expectedASCII) {
                    problems.append("toASCII (\(combination.name)) = \(Vectors.escaped(ascii)), tr46 gives \(Vectors.escaped(expectedASCII))")
                }
                let unicode = TR46.toUnicode(vector.input, options: Self.toUnicodeOptions(combination.toUnicode, normalization: .foundation))
                let expected = vector.toUnicode[unicodeOwners[combination.toUnicode]]
                if !Vectors.sameBytes(unicode.domain, expected.domain) || unicode.hadError != expected.hadError {
                    problems.append("toUnicode (\(combination.name)) = (\(Vectors.escaped(unicode.domain)), \(unicode.hadError)), "
                        + "tr46 gives (\(Vectors.escaped(expected.domain)), \(expected.hadError))")
                }
            }
            if problems.isEmpty { continue }
            let message = "\(Vectors.escaped(vector.input)): \(problems.joined(separator: "; "))"
            if let defect = Self.foundationNFCDefect(vector.input) {
                knownDefects.append("\(message). Foundation's NFC of \(Vectors.escaped(defect.codePoints)) is "
                    + "\(Vectors.escaped(defect.foundation)), the bundled NFC's is \(Vectors.escaped(defect.bundled))")
            } else {
                failures.append(message)
            }
        }
        print("[differential] .foundation: \(vectors.count) inputs without an age × \(Self.foundationCombinations.count) combinations; "
            + "\(failures.count) unexplained differences, \(knownDefects.count) explained by Foundation's NFC")
        #expect(vectors.count > 9_000)
        #expect(compared == vectors.count * Self.foundationCombinations.count)
        #expect(failures.isEmpty, "\(failures.count) differ:\n\(failures.prefix(20).joined(separator: "\n"))")
        // A difference that Foundation's NFC explains is the OS's defect, not the port's: see
        // NormalizationTests.foundationDefects. The bundled NFC is never changed to match it.
        withKnownIssue("Foundation's NFC defects on this OS", isIntermittent: true) {
            #expect(knownDefects.isEmpty, "\(knownDefects.count) known defects:\n\(knownDefects.prefix(20).joined(separator: "\n"))")
        }
    }
    #endif
}
