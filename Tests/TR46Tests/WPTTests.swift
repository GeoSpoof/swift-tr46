import Testing

@testable import TR46

/// web-platform-tests' toascii.json and IdnaTestV2.json at the commit tr46 v7.0.0 tests against,
/// selected and run as tr46's test/toascii.js does (`Resources/wpt-toascii.json`).
@Suite("Conformance: web-platform-tests toascii.json and IdnaTestV2.json")
struct WPTTests {
    /// tr46's test/toascii.js.
    static let options = TR46.Options(checkHyphens: false, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: false, verifyDNSLength: false)

    @Test("every selected case")
    func toASCII() throws {
        let file = try IDNAVectors.wpt()
        try #require(file.counts.toascii == 61 && file.toascii.count == 61, "toascii.json has \(file.toascii.count) cases")
        try #require(file.counts.idnaTestV2 == 1_680 && file.idnaTestV2.count == 1_680, "IdnaTestV2.json has \(file.idnaTestV2.count) cases")

        var passed: [Int] = []
        var failures: [String] = []
        for (name, cases) in [("toascii.json", file.toascii), ("IdnaTestV2.json", file.idnaTestV2)] {
            var count = 0
            for (index, testCase) in cases.enumerated() {
                let actual = TR46.toASCII(testCase.input, options: Self.options)
                if Vectors.sameBytes(actual, testCase.output) {
                    count += 1
                } else {
                    let comment = testCase.comment.map { " (\($0))" } ?? ""
                    failures.append("\(name)[\(index)] \(Vectors.escaped(testCase.input))\(comment): "
                        + "\(Vectors.escaped(actual)), expected \(Vectors.escaped(testCase.output))")
                }
            }
            passed.append(count)
        }

        print(
            "[conformance] WPT \(file.source.commit.prefix(7)): toascii.json \(passed[0])/\(file.toascii.count); "
                + "IdnaTestV2.json \(passed[1])/\(file.idnaTestV2.count)"
        )
        #expect(failures.isEmpty, "\(failures.count) cases fail:\n\(failures.prefix(20).joined(separator: "\n"))")
    }
}
