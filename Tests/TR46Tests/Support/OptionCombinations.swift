import TR46

/// Every combination of `TR46.Options`'s seven Booleans, numbered so that bit j of combination k
/// is option j in plan.md D17's order: checkHyphens, checkBidi, checkJoiners, useSTD3ASCIIRules,
/// transitionalProcessing, verifyDNSLength, ignoreInvalidPunycode.
enum OptionCombinations {
    static let names = [
        "checkHyphens", "checkBidi", "checkJoiners", "useSTD3ASCIIRules",
        "transitionalProcessing", "verifyDNSLength", "ignoreInvalidPunycode",
    ]

    /// Combination `k` of the 128, with `normalization`.
    static func options(_ k: Int, normalization: TR46.Normalization = .bundled) -> TR46.Options {
        TR46.Options(
            checkHyphens: k & 1 != 0,
            checkBidi: k & 2 != 0,
            checkJoiners: k & 4 != 0,
            useSTD3ASCIIRules: k & 8 != 0,
            transitionalProcessing: k & 16 != 0,
            verifyDNSLength: k & 32 != 0,
            ignoreInvalidPunycode: k & 64 != 0,
            normalization: normalization
        )
    }

    /// All 128, in order.
    static let all: [TR46.Options] = (0..<128).map { options($0) }

    /// The options that are on in combination `k`, for messages.
    static func describe(_ k: Int) -> String {
        let on = names.indices.filter { k & (1 << $0) != 0 }.map { names[$0] }
        return on.isEmpty ? "no options" : on.joined(separator: ", ")
    }
}
