import Testing

@testable import TR46

/// The bundled NFC against Unicode 18.0.0's NormalizationTest.txt, re-encoded in
/// `Resources/normalization-test.json` by `Scripts/generate-vectors.mjs`.
@Suite("NFC: Unicode 18.0.0 NormalizationTest")
struct NormalizationTests {
    struct Vector: Decodable, Sendable {
        let part: Int
        /// c1…c5 in the file's hex form, for messages.
        let hex: [String]
        /// c1…c5 as code points.
        let columns: [[UInt32]]
        /// Present only when a code point is newer than Unicode 14.0.
        let age: String?

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            part = try container.decode(Int.self)
            var hex: [String] = []
            for _ in 0..<5 { hex.append(try container.decode(String.self)) }
            self.hex = hex
            age = container.isAtEnd ? nil : try container.decode(String.self)
            if !container.isAtEnd {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "a vector has more than 7 fields")
            }
            columns = try hex.map { try Vectors.codePoints(hex: $0) }
        }
    }

    struct File: Decodable, Sendable {
        let counts: [String: Int]
        let vectors: [Vector]
    }

    static let expectedCounts = ["part0": 46, "part1": 17154, "part2": 2004, "part3": 194, "part4": 735, "part5": 38]

    static func load() throws -> File {
        let file = try Vectors.load(File.self, from: "normalization-test")
        try #require(file.counts == expectedCounts, "counts are \(file.counts)")
        try #require(file.vectors.count == expectedCounts.values.reduce(0, +))
        for (part, count) in expectedCounts {
            try #require(file.vectors.filter { "part\($0.part)" == part }.count == count, "\(part) has the wrong count")
        }
        return file
    }

    private static func place(_ index: Int, _ vector: Vector) -> String {
        "vector \(index) (part \(vector.part)) [\(vector.hex.joined(separator: "; "))]"
    }

    @Test("every NFC invariant holds, and NFC(X) == X for every code point outside Part 1")
    func conformance() throws {
        let file = try Self.load()
        var failures: [String] = []
        var passedLines = 0
        for (index, vector) in file.vectors.enumerated() {
            // c2 == toNFC(c1) == toNFC(c2) == toNFC(c3), and c4 == toNFC(c4) == toNFC(c5).
            var lineFailures: [String] = []
            for (expected, inputs) in [(1, [0, 1, 2]), (3, [3, 4])] {
                for input in inputs {
                    let actual = NFC.normalize(vector.columns[input])
                    if actual != vector.columns[expected] {
                        lineFailures.append("\(Self.place(index, vector)): NFC(c\(input + 1)) = \(Vectors.escaped(actual)), expected c\(expected + 1)")
                    }
                }
            }
            if lineFailures.isEmpty { passedLines += 1 } else { failures += lineFailures }
        }

        // Part 2 of the conformance clause: everything Part 1 doesn't list is its own NFC.
        // Surrogates are left out, because a decoded label holding one never reaches NFC.
        var part1 = Set<UInt32>()
        for vector in file.vectors where vector.part == 1 {
            try #require(vector.columns[0].count == 1, "a Part 1 vector with \(vector.columns[0].count) code points")
            part1.insert(vector.columns[0][0])
        }
        var outside = 0
        var outsidePassed = 0
        for codePoint in UInt32(0)...0x10FFFF where !(0xD800...0xDFFF).contains(codePoint) && !part1.contains(codePoint) {
            outside += 1
            let actual = NFC.normalize([codePoint])
            if actual == [codePoint] {
                outsidePassed += 1
            } else {
                failures.append("NFC(U+\(String(codePoint, radix: 16, uppercase: true))) = \(Vectors.escaped(actual)), outside Part 1")
            }
        }

        print(
            "[conformance] NormalizationTest \(NFCTables.unicodeVersion): \(passedLines)/\(file.vectors.count) lines; "
                + "outside part 1: \(outsidePassed)/\(outside) code points"
        )
        #expect(passedLines == file.vectors.count && outsidePassed == outside,
                "\(failures.count) failures:\n\(failures.prefix(20).joined(separator: "\n"))")
    }

    @Test("the quick check and isNormalized agree with the full algorithm on every vector")
    func quickCheckAgreesWithNormalize() throws {
        let file = try Self.load()
        var failures: [String] = []
        for (index, vector) in file.vectors.enumerated() {
            for (column, codePoints) in vector.columns.enumerated() {
                let full = NFC.decomposeAndCompose(codePoints)
                let isNFC = full == codePoints
                let quickCheck = NFC.quickCheck(codePoints)
                var problems: [String] = []
                if quickCheck == .yes && !isNFC { problems.append("quick check yes on non-NFC text") }
                if quickCheck == .no && isNFC { problems.append("quick check no on NFC text") }
                if NFC.isNormalized(codePoints) != isNFC { problems.append("isNormalized is \(!isNFC)") }
                if NFC.normalize(codePoints) != full { problems.append("normalize differs from the full algorithm") }
                if !problems.isEmpty {
                    failures.append("\(Self.place(index, vector)) c\(column + 1): \(problems.joined(separator: ", "))")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures:\n\(failures.prefix(20).joined(separator: "\n"))")
    }

    #if canImport(Darwin)
    /// Inputs on which Foundation's `precomposedStringWithCanonicalMapping` gives the wrong NFC,
    /// measured on macOS 27.0.1. NormalizationTest, ICU (Node's `normalize`) and the bundled NFC
    /// all agree on the right answer. Foundation:
    /// - leaves a precomposed LV syllable followed by a trailing consonant as it is. NFC of
    ///   U+1100 U+AC00 U+11A8 is U+1100 U+AC01 (the same with a second U+11A8 after it).
    /// - drops U+11A7, which is the TBase and not a trailing consonant: NFC of
    ///   U+1100 U+1161 U+11A7 is U+AC00 U+11A7, and Foundation returns U+AC00.
    /// - leaves U+0CCA U+0CD5 as it is. NFC is U+0CCB, which it does produce from the decomposed
    ///   U+0CC6 U+0CC2 U+0CD5.
    /// These are Foundation's defects, recorded as known issues and never worked around in the
    /// bundled NFC. They are intermittent because they depend on the OS the tests run on.
    static let foundationDefects: [[UInt32]] = [
        [0x1100, 0xAC00, 0x11A8],
        [0x1100, 0xAC00, 0x11A8, 0x11A8],
        [0x1100, 0x1161, 0x11A7],
        [0x0CCA, 0x0CD5],
    ]

    @Test("Foundation's NFC agrees with the bundled NFC on every vector without an age")
    func foundationAgrees() throws {
        let file = try Self.load()
        let bundled = Normalizer(mode: .bundled)
        let foundation = Normalizer(mode: .foundation)
        var failures: [String] = []
        var knownDefects: [String] = []
        var compared = 0
        for (index, vector) in file.vectors.enumerated() where vector.age == nil {
            for (column, codePoints) in vector.columns.enumerated() {
                compared += 1
                let expected = bundled.nfc(codePoints)
                let actual = foundation.nfc(codePoints)
                if actual != expected || foundation.isNFC(codePoints) != bundled.isNFC(codePoints) {
                    let failure = "\(Self.place(index, vector)) c\(column + 1): Foundation gives \(Vectors.escaped(actual))"
                    if Self.foundationDefects.contains(codePoints) {
                        knownDefects.append(failure)
                    } else {
                        failures.append(failure)
                    }
                }
            }
        }
        #expect(compared > 0)
        #expect(failures.isEmpty, "\(failures.count) of \(compared) differ:\n\(failures.prefix(20).joined(separator: "\n"))")
        withKnownIssue("Foundation's NFC defects on this OS; see foundationDefects", isIntermittent: true) {
            #expect(knownDefects.isEmpty, "\(knownDefects.count) known defects:\n\(knownDefects.joined(separator: "\n"))")
        }
    }
    #endif
}
