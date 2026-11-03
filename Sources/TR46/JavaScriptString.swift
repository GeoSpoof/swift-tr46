// The parts of JavaScript's UTF-16 string semantics that tr46 7.0.0 and punycode.js 2.3.1 depend
// on, over code points. Documentation.docc/BehaviourFromJavaScript.md describes each of J1–J12,
// the labels used below, and why it matters.
// tr46 7.0.0 index.js, Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

/// A label is held as `[UInt32]`, the values a JavaScript `for…of` loop yields over tr46's string:
/// code points, and a lone surrogate as its own value. A Swift `String` can't hold a lone
/// surrogate, but a label decoded from Punycode can (J1, J3), so nothing here goes through
/// `String` until the very end.
///
/// The other direction can't happen at all (J4): an input is a `String`, so it never holds a lone
/// surrogate. The two IdnaTestV2 rows and two WPT inputs that do are skipped by the tests.
///
/// Reading UTF-16 units instead of code points makes no difference anywhere else (J7). punycode.js's
/// `decode` indexes its input with `lastIndexOf` and `charCodeAt`, but any non-ASCII unit fails it
/// whichever way it is indexed: before the last `-` it is `not-basic`, and after it `basicToDigit`
/// returns `base`, which is `invalid-input`. `Punycode.decode` reads code points and fails the same
/// inputs.
enum JSString {
    /// tr46's `containsNonASCII(str)`, `/[^\x00-\x7F]/u.test(str)`: any value above U+007F. A lone
    /// surrogate counts, as it does in the regex.
    static func containsNonASCII<C: Collection>(_ label: C) -> Bool where C.Element == UInt32 {
        label.contains { $0 > 0x7F }
    }

    /// What tr46 iterates after punycode.js's `String.fromCodePoint(...output)`.
    ///
    /// - J2: `fromCodePoint` throws a `RangeError` for a value above U+10FFFF, and tr46 catches it
    ///   as a decoding failure, so this returns nil.
    /// - J1: `fromCodePoint` accepts surrogate values, and the result is a UTF-16 string, so a high
    ///   surrogate value followed by a low one becomes a single supplementary code point when the
    ///   string is iterated. Any other surrogate value stays a lone one. `xn--8c9bk9h` decodes to
    ///   D83D, DE00, which tr46 reads as U+1F600 and re-encodes as `xn--e28h`.
    ///
    /// Not reproduced (J12): the spread `fromCodePoint(...output)` passes one argument per code
    /// point, and on Node 24.12.0 it throws "Maximum call stack size exceeded" somewhere between
    /// 120,000 and 125,000 of them. That limit depends on the engine and the stack, so this decodes
    /// any length.
    static func fromCodePoints(_ values: [UInt32]) -> [UInt32]? {
        if values.contains(where: { $0 > 0x10FFFF }) { return nil }
        // The UTF-16 units of the string fromCodePoint builds…
        var units: [UInt32] = []
        units.reserveCapacity(values.count)
        for value in values {
            if value > 0xFFFF {
                let offset = value - 0x10000
                units.append(0xD800 + (offset >> 10))
                units.append(0xDC00 + (offset & 0x3FF))
            } else {
                units.append(value)
            }
        }
        // …iterated by code point, as for…of and Array.from do.
        var result: [UInt32] = []
        result.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if (0xD800...0xDBFF).contains(unit), index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) {
                result.append(0x10000 + ((unit - 0xD800) << 10) + (units[index + 1] - 0xDC00))
                index += 2
            } else {
                result.append(unit)
                index += 1
            }
        }
        return result
    }

    /// tr46's `labels.join(".")` as a Swift `String`, with every lone surrogate replaced by U+FFFD,
    /// as JavaScript's `String.prototype.toWellFormed()` does (J3).
    ///
    /// Joining can't pair surrogates across labels, because a U+002E separates them, and
    /// `fromCodePoints` has already paired any within a label. So each value is either a code
    /// point or a lone surrogate.
    ///
    /// tr46 can only return a lone surrogate together with an error. It can appear only in a
    /// decoded label, which is then either not validated, because the error is already set, or
    /// validated and refused: every step of `validateLabel` before step 7 can only refuse a label,
    /// and step 7 refuses D800–DFFF in both modes, because they are disallowed (the generator
    /// asserts it). So a replaced surrogate always comes with `hadError == true`.
    static func wellFormedString(joining labels: [[UInt32]]) -> String {
        var scalars = String.UnicodeScalarView()
        for (index, label) in labels.enumerated() {
            if index > 0 { scalars.append(".") }
            for value in label {
                scalars.append(Unicode.Scalar(value) ?? "\u{FFFD}")
            }
        }
        return String(scalars)
    }
}
