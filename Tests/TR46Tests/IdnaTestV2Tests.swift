import Testing

@testable import TR46

/// Unicode 18.0.0's IdnaTestV2.txt, as `Resources/idna-test-v2.json` resolves it, under the options
/// of tr46's test/unicode.js at v7.0.0, read strictly: inherited statuses, toASCII
/// compared exactly, and toUnicode's domain and error compared on every row. Real tr46 7.0.0 passes
/// every row this way, and the generator asserts it.
@Suite("Conformance: Unicode 18.0.0 IdnaTestV2")
struct IdnaTestV2Tests {
    typealias Vector = IDNAVectors.IdnaTestV2Vector

    static let expectedCounts = IDNAVectors.IdnaTestV2Counts(lines: 6_396, skippedLoneSurrogate: 2, vectors: 6_394)

    static func load() throws -> IDNAVectors.IdnaTestV2File {
        let file = try IDNAVectors.idnaTestV2()
        try #require(file.counts == expectedCounts, "counts are \(file.counts)")
        try #require(file.vectors.count == expectedCounts.vectors)
        return file
    }

    /// tr46's test/unicode.js: toUnicode with every check on.
    static func toUnicodeOptions(_ normalization: TR46.Normalization) -> TR46.Options {
        TR46.Options(checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true, normalization: normalization)
    }

    /// tr46's test/unicode.js: toASCII with every check on and verifyDNSLength, N or T.
    static func toASCIIOptions(transitional: Bool, _ normalization: TR46.Normalization) -> TR46.Options {
        TR46.Options(
            checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true,
            transitionalProcessing: transitional, verifyDNSLength: true, normalization: normalization
        )
    }

    struct Tally {
        var lines = 0
        var toUnicode = 0
        var toASCIIN = 0
        var toASCIIT = 0
        var failures: [(vector: Vector, message: String)] = []
    }

    static func run(_ vectors: [Vector], _ normalization: TR46.Normalization) -> Tally {
        var tally = Tally()
        let unicodeOptions = toUnicodeOptions(normalization)
        let nOptions = toASCIIOptions(transitional: false, normalization)
        let tOptions = toASCIIOptions(transitional: true, normalization)
        for vector in vectors {
            var problems: [String] = []
            let unicode = TR46.toUnicode(vector.source, options: unicodeOptions)
            if Vectors.sameBytes(unicode.domain, vector.toUnicode) && unicode.hadError == vector.toUnicodeError {
                tally.toUnicode += 1
            } else {
                problems.append("toUnicode (\(Vectors.escaped(unicode.domain)), \(unicode.hadError)), "
                    + "expected (\(Vectors.escaped(vector.toUnicode)), \(vector.toUnicodeError))")
            }
            let asciiN = TR46.toASCII(vector.source, options: nOptions)
            if Vectors.sameBytes(asciiN, vector.toASCIIN) {
                tally.toASCIIN += 1
            } else {
                problems.append("toASCII-N \(Vectors.escaped(asciiN)), expected \(Vectors.escaped(vector.toASCIIN))")
            }
            let asciiT = TR46.toASCII(vector.source, options: tOptions)
            if Vectors.sameBytes(asciiT, vector.toASCIIT) {
                tally.toASCIIT += 1
            } else {
                problems.append("toASCII-T \(Vectors.escaped(asciiT)), expected \(Vectors.escaped(vector.toASCIIT))")
            }
            if problems.isEmpty {
                tally.lines += 1
            } else {
                tally.failures.append((vector, problems.joined(separator: "; ")))
            }
        }
        return tally
    }

    static func describe(_ failures: [(vector: Vector, message: String)]) -> String {
        failures.prefix(20).map { "IdnaTestV2.txt:\($0.vector.line) \(Vectors.escaped($0.vector.source)): \($0.message)" }
            .joined(separator: "\n")
    }

    @Test("every row, with the bundled NFC")
    func bundled() throws {
        let file = try Self.load()
        let tally = Self.run(file.vectors, .bundled)
        let count = file.vectors.count
        print(
            "[conformance] IdnaTestV2 \(TR46.unicodeVersion): \(tally.lines)/\(file.counts.lines) lines "
                + "(\(file.counts.skippedLoneSurrogate) lone-surrogate skipped); toUnicode \(tally.toUnicode)/\(count); "
                + "toASCII-N \(tally.toASCIIN)/\(count); toASCII-T \(tally.toASCIIT)/\(count)"
        )
        #expect(tally.failures.isEmpty, "\(tally.failures.count) rows fail:\n\(Self.describe(tally.failures))")
    }

    #if canImport(Darwin)
    @Test("every row without an age, with Foundation's NFC")
    func foundation() throws {
        let file = try Self.load()
        let vectors = file.vectors.filter { $0.age == nil }
        let tally = Self.run(vectors, .foundation)
        print(
            "[conformance] IdnaTestV2 \(TR46.unicodeVersion) (.foundation): \(tally.lines)/\(vectors.count) rows without an age; "
                + "toUnicode \(tally.toUnicode)/\(vectors.count); toASCII-N \(tally.toASCIIN)/\(vectors.count); "
                + "toASCII-T \(tally.toASCIIT)/\(vectors.count)"
        )
        #expect(vectors.count > 6_000)
        #expect(tally.failures.isEmpty, "\(tally.failures.count) rows fail:\n\(Self.describe(tally.failures))")
    }
    #endif
}
