/// The IDNA vector files in `Resources/`, as `Scripts/generate-vectors.mjs` writes them (plan.md §9),
/// and the GeoSpoof fixture, which is copied as it is.
enum IDNAVectors {
    // MARK: idna-test-v2.json

    struct IdnaTestV2Vector: Decodable, Sendable {
        /// The line in IdnaTestV2.txt.
        let line: Int
        let source: String
        let toUnicode: String
        let toUnicodeError: Bool
        /// nil where toASCII must fail.
        let toASCIIN: String?
        let toASCIIT: String?
        /// Present only when a code point the vector passes through is newer than Unicode 14.0.
        let age: String?
    }

    struct IdnaTestV2Counts: Decodable, Sendable, Equatable {
        let lines: Int
        let skippedLoneSurrogate: Int
        let vectors: Int
    }

    struct IdnaTestV2File: Decodable, Sendable {
        let counts: IdnaTestV2Counts
        let vectors: [IdnaTestV2Vector]
    }

    static func idnaTestV2() throws -> IdnaTestV2File {
        try Vectors.load(IdnaTestV2File.self, from: "idna-test-v2")
    }

    // MARK: wpt-toascii.json

    struct WPTCase: Decodable, Sendable {
        let input: String
        /// nil where toASCII must fail.
        let output: String?
        let comment: String?
    }

    struct WPTCounts: Decodable, Sendable {
        let toascii: Int
        let idnaTestV2: Int
    }

    struct WPTFile: Decodable, Sendable {
        let source: WPTSource
        let counts: WPTCounts
        let toascii: [WPTCase]
        let idnaTestV2: [WPTCase]
    }

    struct WPTSource: Decodable, Sendable {
        let commit: String
    }

    static func wpt() throws -> WPTFile {
        try Vectors.load(WPTFile.self, from: "wpt-toascii")
    }

    // MARK: geospoof-idna-vectors.json

    struct GeoSpoofVector: Decodable, Sendable {
        /// The line in IdnaTestV2.txt, for the idnaTestV2 group.
        let line: Int?
        /// The curated group's label.
        let note: String?
        let input: String
        /// What the GeoSpoof extension's hostToASCII returned; nil for its null.
        let ascii: String?
    }

    struct GeoSpoofCounts: Decodable, Sendable, Equatable {
        let curated: Int
        let idnaTestV2: Int
    }

    struct GeoSpoofFile: Decodable, Sendable {
        let tr46: String
        let counts: GeoSpoofCounts
        let curated: [GeoSpoofVector]
        let idnaTestV2: [GeoSpoofVector]
    }

    static func geoSpoof() throws -> GeoSpoofFile {
        try Vectors.load(GeoSpoofFile.self, from: "geospoof-idna-vectors")
    }

    // MARK: All inputs

    /// Every domain input in the three files, in file order, duplicates included.
    static func allInputs() throws -> [String] {
        let wpt = try wpt()
        let geoSpoof = try geoSpoof()
        return try idnaTestV2().vectors.map(\.source)
            + (wpt.toascii + wpt.idnaTestV2).map(\.input)
            + (geoSpoof.curated + geoSpoof.idnaTestV2).map(\.input)
    }
}
