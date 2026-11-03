import Foundation

/// Loading, comparing and printing the JSON vectors in `Resources/`.
///
/// Strings are compared as UTF-8 bytes and code points as `[UInt32]`, never with `String ==`,
/// which is canonical equivalence and would pass an answer that differs only in normalization.
enum Vectors {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    /// `Resources/<name>.json` in the test bundle.
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw LoadError(
                description: "Resources/\(name).json is not in the test bundle. "
                    + "Run Scripts/regenerate.sh, and check that Package.swift copies Resources."
            )
        }
        return url
    }

    /// Decodes `Resources/<name>.json`, naming the file in any error.
    static func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let url = try url(name)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError(description: "can't read \(url.path): \(error)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoadError(description: "Resources/\(name).json doesn't decode as \(T.self): \(error)")
        }
    }

    /// The UCD's hex form, "0044 0307", as code points.
    static func codePoints(hex: String) throws -> [UInt32] {
        try hex.split(separator: " ", omittingEmptySubsequences: false).map { part in
            guard (4...6).contains(part.count), let value = UInt32(part, radix: 16), value <= 0x10FFFF else {
                throw LoadError(description: "\"\(hex)\" is not a sequence of code points")
            }
            return value
        }
    }

    /// A string's code points, in order.
    static func codePoints(_ string: String) -> [UInt32] {
        string.unicodeScalars.map(\.value)
    }

    /// A string's UTF-8 bytes, for an exact comparison; nil stays nil.
    static func bytes(_ string: String?) -> [UInt8]? {
        string.map { Array($0.utf8) }
    }

    /// Whether two optional strings hold exactly the same code units.
    static func sameBytes(_ a: String?, _ b: String?) -> Bool {
        bytes(a) == bytes(b)
    }

    /// A string as Swift source would spell it, with everything outside printable ASCII escaped,
    /// so a failure message names the exact code points.
    static func escaped(_ string: String?) -> String {
        guard let string else { return "nil" }
        return escaped(codePoints(string))
    }

    /// Code points as a quoted Swift string literal, surrogate values included.
    static func escaped(_ codePoints: [UInt32]) -> String {
        "\"" + codePoints.map { value -> String in
            if (0x20...0x7E).contains(value), value != 0x22, value != 0x5C, let scalar = Unicode.Scalar(value) {
                return String(Character(scalar))
            }
            return "\\u{\(String(value, radix: 16, uppercase: true))}"
        }.joined() + "\""
    }
}

/// SplitMix64: a deterministic generator, so a test that draws random inputs draws the same ones
/// on every run and every platform.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// The default seed is "tr46" in ASCII, as in Scripts/lib/fuzz.mjs.
    init(seed: UInt64 = 0x7472_3436) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
