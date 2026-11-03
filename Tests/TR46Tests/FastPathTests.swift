import Testing

@testable import TR46

/// The ASCII fast path (plan.md D6) against the table path: `Processing.process` with
/// `asciiFastPath` true and false must give the same labels and error, for every all-ASCII input
/// in the vector files and 2,000 drawn ASCII strings, under all 128 option combinations.
@Suite("ASCII fast path")
struct FastPathTests {
    /// ASCII strings shaped like domains: labels of letters in both cases, digits, hyphens and
    /// `xn--` prefixes, with now and then any other ASCII code point, controls included.
    static func drawnInputs(_ count: Int) -> [String] {
        var generator = SeededGenerator(seed: 0x7472_3436 ^ 0xFA57)
        let common = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-".unicodeScalars)
        return (0..<count).map { _ in
            var scalars = String.UnicodeScalarView()
            for label in 0..<Int.random(in: 1...4, using: &generator) {
                if label > 0 { scalars.append(".") }
                switch UInt32.random(in: 0..<10, using: &generator) {
                case 0: scalars.append(contentsOf: "xn--".unicodeScalars)
                case 1: scalars.append(contentsOf: "XN--".unicodeScalars)
                case 2: scalars.append("-")
                default: break
                }
                for _ in 0..<Int.random(in: 0...12, using: &generator) {
                    if UInt32.random(in: 0..<10, using: &generator) == 0 {
                        scalars.append(Unicode.Scalar(UInt8.random(in: 0..<0x80, using: &generator)))
                    } else {
                        scalars.append(common.randomElement(using: &generator)!)
                    }
                }
            }
            return String(scalars)
        }
    }

    @Test("asciiFastPath true and false agree under all 128 option combinations")
    func fastPathMatchesTablePath() async throws {
        // Deduplicated by UTF-8 bytes, never by String, whose == is canonical equivalence.
        var seen = Set<[UInt8]>()
        var fromFiles: [String] = []
        for input in try IDNAVectors.allInputs() where input.unicodeScalars.allSatisfy(\.isASCII) {
            if seen.insert(Array(input.utf8)).inserted { fromFiles.append(input) }
        }
        let drawn = Self.drawnInputs(2_000)
        let inputs = fromFiles + drawn
        #expect(fromFiles.count > 2_000, "only \(fromFiles.count) all-ASCII inputs in the vector files")

        let combinations = OptionCombinations.all
        let failures = await withTaskGroup(of: [String].self) { group in
            let shards = 16
            for shard in 0..<shards {
                group.addTask {
                    var failures: [String] = []
                    for index in stride(from: shard, to: inputs.count, by: shards) {
                        let input = inputs[index]
                        for (k, options) in combinations.enumerated() {
                            let fast = Processing.process(input, options: options, asciiFastPath: true)
                            let table = Processing.process(input, options: options, asciiFastPath: false)
                            if fast.labels != table.labels || fast.error != table.error {
                                failures.append("\(Vectors.escaped(input)) with \(OptionCombinations.describe(k)): "
                                    + "fast path error \(fast.error), table path error \(table.error)")
                            }
                        }
                    }
                    return failures
                }
            }
            var all: [String] = []
            for await part in group { all += part }
            return all
        }
        #expect(failures.isEmpty, "\(failures.count) differ:\n\(failures.prefix(20).joined(separator: "\n"))")
        print("[fast path] \(fromFiles.count) inputs from the vector files + \(drawn.count) drawn, × \(combinations.count) option combinations: \(failures.isEmpty ? "all agree" : "\(failures.count) differ")")
    }
}
