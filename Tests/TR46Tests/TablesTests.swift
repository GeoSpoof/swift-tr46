import Testing

@testable import TR46

/// The generated tables: their structure, the facts the port relies on, and their versions.
@Suite("Generated tables")
struct TablesTests {
    static let classes: [(name: String, ranges: [UInt32])] = [
        ("combiningMarks", IDNATables.combiningMarks),
        ("combiningClassVirama", IDNATables.combiningClassVirama),
        ("validZWNJBefore", IDNATables.validZWNJBefore),
        ("validZWNJTransparentBefore", IDNATables.validZWNJTransparentBefore),
        ("validZWNJTransparentAfter", IDNATables.validZWNJTransparentAfter),
        ("validZWNJAfter", IDNATables.validZWNJAfter),
        ("bidiDomain", IDNATables.bidiDomain),
        ("bidiS1LTR", IDNATables.bidiS1LTR),
        ("bidiS1RTL", IDNATables.bidiS1RTL),
        ("bidiS2", IDNATables.bidiS2),
        ("bidiS3Last", IDNATables.bidiS3Last),
        ("bidiS3Trailing", IDNATables.bidiS3Trailing),
        ("bidiS4EN", IDNATables.bidiS4EN),
        ("bidiS4AN", IDNATables.bidiS4AN),
        ("bidiS5", IDNATables.bidiS5),
        ("bidiS6Last", IDNATables.bidiS6Last),
        ("bidiS6Trailing", IDNATables.bidiS6Trailing),
    ]

    /// The classes an all-ASCII label or domain never consults, under the ASCII fast path.
    static let fastPathClasses: [(name: String, ranges: [UInt32])] = [
        ("combiningMarks", IDNATables.combiningMarks),
        ("combiningClassVirama", IDNATables.combiningClassVirama),
        ("validZWNJBefore", IDNATables.validZWNJBefore),
        ("validZWNJTransparentBefore", IDNATables.validZWNJTransparentBefore),
        ("validZWNJTransparentAfter", IDNATables.validZWNJTransparentAfter),
        ("validZWNJAfter", IDNATables.validZWNJAfter),
        ("bidiDomain", IDNATables.bidiDomain),
    ]

    private static func isStrictlyIncreasing<T: Comparable>(_ values: [T]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Sorted inclusive [lo, hi] pairs: an even count, lo ≤ hi, and each pair after the last.
    private static func areSortedPairs(_ ranges: [UInt32]) -> Bool {
        guard ranges.count % 2 == 0 else { return false }
        for index in stride(from: 0, to: ranges.count, by: 2) {
            if ranges[index] > ranges[index + 1] || ranges[index + 1] > 0x10FFFF { return false }
            if index > 0 && ranges[index] <= ranges[index - 1] { return false }
        }
        return true
    }

    @Test("the mapping table is well formed")
    func mappingTableIsWellFormed() {
        let starts = IDNATables.starts
        #expect(starts.first == 0)
        #expect(Self.isStrictlyIncreasing(starts), "starts must be strictly increasing")
        #expect((starts.last ?? 0) <= 0x10FFFF)
        #expect(IDNATables.entries.count == starts.count)
        let pool = IDNATables.mappingScalars.count
        for (index, entry) in IDNATables.entries.enumerated() {
            let length = Int((entry >> 3) & 0x1F)
            let offset = Int(entry >> 8)
            #expect(Status(rawValue: entry & 0x7) != nil, "entry \(index) has status \(entry & 0x7)")
            #expect(offset + length <= pool, "entry \(index) reaches past the pool")
        }
    }

    @Test("every class table is sorted inclusive pairs")
    func classTablesAreSortedPairs() {
        for (name, ranges) in Self.classes {
            #expect(!ranges.isEmpty, "\(name) is empty")
            #expect(Self.areSortedPairs(ranges), "\(name) isn't sorted inclusive pairs")
        }
    }

    @Test("tr46's rows for the code points the port relies on")
    func spotChecks() {
        let cases: [(UInt32, Status, [UInt32])] = [
            (0x41, .mapped, [0x61]),            // A → a
            (0xDF, .deviation, [0x73, 0x73]),   // ß → ss, read only under transitional processing
            (0x3C2, .deviation, [0x3C3]),       // ς → σ
            (0x200C, .deviation, []),           // ZWNJ → ""
            (0x200D, .deviation, []),           // ZWJ → ""
            (0x1E9E, .mapped, [0xDF]),          // ẞ → ß
            (0x2E, .valid, []),                 // the full stop the port splits on
        ]
        for (codePoint, status, mapping) in cases {
            let (actual, actualMapping) = Lookup.status(of: codePoint)
            #expect(actual == status, "U+\(String(codePoint, radix: 16, uppercase: true))")
            #expect(Array(actualMapping) == mapping, "U+\(String(codePoint, radix: 16, uppercase: true))")
        }
        let surrogates = (UInt32(0xD800)...0xDFFF).filter { Lookup.status(of: $0).0 != .disallowed }
        #expect(surrogates.isEmpty, "surrogates not disallowed: \(surrogates.prefix(5))")
    }

    @Test("ASCII: A–Z map to lower case, every other code point is valid, as the ASCII fast path assumes")
    func asciiRows() {
        for codePoint in UInt32(0)...0x7F {
            let (status, mapping) = Lookup.status(of: codePoint)
            if (0x41...0x5A).contains(codePoint) {
                #expect(status == .mapped && Array(mapping) == [codePoint + 0x20], "U+\(String(codePoint, radix: 16))")
            } else {
                #expect(status == .valid && mapping.isEmpty, "U+\(String(codePoint, radix: 16))")
            }
        }
    }

    @Test("no ASCII code point is in a class the ASCII fast path skips")
    func noASCIIInFastPathClasses() {
        for (name, ranges) in Self.fastPathClasses {
            let ascii = (UInt32(0)...0x7F).filter { Lookup.contains(ranges, $0) }
            #expect(ascii.isEmpty, "\(name) contains \(ascii)")
        }
    }

    @Test("the NFC tables are well formed")
    func nfcTablesAreWellFormed() {
        #expect(NFCTables.cccStarts.first == 0)
        #expect(Self.isStrictlyIncreasing(NFCTables.cccStarts))
        #expect(NFCTables.cccStarts.count == NFCTables.cccValues.count)
        #expect(zip(NFCTables.cccValues, NFCTables.cccValues.dropFirst()).allSatisfy { $0 != $1 }, "adjacent runs must differ")

        #expect(Self.isStrictlyIncreasing(NFCTables.decompositionKeys))
        #expect(NFCTables.decompositionKeys.count == NFCTables.decompositionEntries.count)
        let pool = NFCTables.decompositionPool.count
        for (index, entry) in NFCTables.decompositionEntries.enumerated() {
            let length = Int(entry & 0x7)
            #expect(length >= 1 && Int(entry >> 3) + length <= pool, "decomposition entry \(index)")
        }

        #expect(Self.isStrictlyIncreasing(NFCTables.compositionKeys))
        #expect(NFCTables.compositionKeys.count == NFCTables.compositionValues.count)
        #expect(Self.areSortedPairs(NFCTables.quickCheckNo))
        #expect(Self.areSortedPairs(NFCTables.quickCheckMaybe))
    }

    @Test("the tables' versions are the package's")
    func versions() {
        #expect(Array(IDNATables.tr46Version.utf8) == Array(TR46.upstreamVersion.utf8))
        #expect(Array(IDNATables.tr46UnicodeVersion.utf8) == Array(TR46.unicodeVersion.utf8))
        #expect(Array(NFCTables.unicodeVersion.utf8) == Array(TR46.unicodeVersion.utf8))
    }
}
