import Testing

@testable import TR46

/// GeoSpoof's parity fixture (`Resources/geospoof-idna-vectors.json`, copied unchanged): the answers
/// the GeoSpoof browser extension's hostToASCII gave, by running tr46 7.0.0, for 3,769 inputs.
/// hostToASCII is tr46's toASCII with the WHATWG URL Standard's options (checkBidi and
/// checkJoiners on, everything else off), plus one rule of its own: an empty result is null.
@Suite("Conformance: the GeoSpoof extension's fixture")
struct GeoSpoofFixtureTests {
    static let expectedCounts = IDNAVectors.GeoSpoofCounts(curated: 59, idnaTestV2: 3_710)

    /// The extension's hostToASCII, through this package.
    static func hostToASCII(_ input: String, _ normalization: TR46.Normalization) -> String? {
        let options = TR46.Options(checkBidi: true, checkJoiners: true, normalization: normalization)
        return TR46.toASCII(input, options: options).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func run(_ normalization: TR46.Normalization) throws -> (passed: Int, total: Int, failures: [String]) {
        let file = try IDNAVectors.geoSpoof()
        try #require(file.tr46 == TR46.upstreamVersion)
        try #require(file.counts == expectedCounts, "counts are \(file.counts)")
        try #require(file.curated.count == expectedCounts.curated && file.idnaTestV2.count == expectedCounts.idnaTestV2)

        var passed = 0
        var failures: [String] = []
        for (group, vectors) in [("curated", file.curated), ("idnaTestV2", file.idnaTestV2)] {
            for (index, vector) in vectors.enumerated() {
                let actual = hostToASCII(vector.input, normalization)
                if Vectors.sameBytes(actual, vector.ascii) {
                    passed += 1
                } else {
                    let place = vector.line.map { "IdnaTestV2.txt:\($0)" } ?? "\(group)[\(index)]"
                    failures.append("\(place) \(Vectors.escaped(vector.input)): \(Vectors.escaped(actual)), expected \(Vectors.escaped(vector.ascii))")
                }
            }
        }
        return (passed, file.curated.count + file.idnaTestV2.count, failures)
    }

    @Test("every vector, with the bundled NFC")
    func bundled() throws {
        let result = try Self.run(.bundled)
        print("[conformance] GeoSpoof fixture: \(result.passed)/\(result.total) (.bundled)")
        #expect(result.failures.isEmpty, "\(result.failures.count) differ:\n\(result.failures.prefix(20).joined(separator: "\n"))")
    }

    #if canImport(Darwin)
    /// The fixture already leaves out every input, and every toUnicode result, holding a code
    /// point that Node's Unicode 16.0 data doesn't assign, so it needs no age filter here.
    @Test("every vector, with Foundation's NFC")
    func foundation() throws {
        let result = try Self.run(.foundation)
        print("[conformance] GeoSpoof fixture: \(result.passed)/\(result.total) (.foundation)")
        #expect(result.failures.isEmpty, "\(result.failures.count) differ:\n\(result.failures.prefix(20).joined(separator: "\n"))")
    }
    #endif
}
