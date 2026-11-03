// Ported from tr46 7.0.0 index.js (validateLabel) and the regexes it uses from lib/regexes.js.
// Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

/// UTS #46 section 4.1, Validity Criteria, as tr46's `validateLabel` checks them, in its order.
///
/// tr46 tests regexes.js's classes on strings with the `u` flag, so membership goes by code point,
/// and a lone surrogate by its raw value (J10). Here each class is a range table in `IDNATables`,
/// tested with `Lookup.contains`.
enum Validation {
    /// tr46's `validateLabel(label, { checkHyphens, checkBidi, checkJoiners, transitionalProcessing,
    /// useSTD3ASCIIRules, isBidi })`. `transitionalProcessing` is passed separately because tr46
    /// turns it off for a decoded label.
    static func validateLabel(
        _ label: [UInt32],
        options: TR46.Options,
        transitionalProcessing: Bool,
        isBidi: Bool,
        normalizer: Normalizer,
        asciiFastPath: Bool = true
    ) -> Bool {
        // "must be satisfied for a non-empty label"
        if label.isEmpty {
            return true
        }

        // Not a step of tr46's. Only a decoded label can hold a lone surrogate, and tr46 refuses
        // every such label: each step before 7 can only return false, and step 7 refuses D800–DFFF
        // in both modes because they are disallowed (Scripts/generate-tables.mjs asserts it).
        // Refusing it here gives the same answer, and keeps a surrogate away from NFC.
        if label.contains(where: { (0xD800...0xDFFF).contains($0) }) {
            return false
        }

        // D6: an all-ASCII label is already in NFC, can't begin with a combining mark, holds no
        // joiner, and has the statuses checked below without the table.
        let isASCII = asciiFastPath && !JSString.containsNonASCII(label)

        // "1. The label must be in Unicode Normalization Form NFC."
        if !isASCII && !normalizer.isNFC(label) {
            return false
        }

        // `const codePoints = Array.from(label);` is `label` itself: it is already code points.

        // "2. If CheckHyphens, the label must not contain a U+002D HYPHEN-MINUS character in both the
        // third and fourth positions."
        //
        // "3. If CheckHyphens, the label must neither begin nor end with a U+002D HYPHEN-MINUS character."
        //
        // The positions count code points, as Array.from does (J5).
        if options.checkHyphens {
            if (label.count >= 4 && label[2] == 0x2D && label[3] == 0x2D) ||
                (label.first == 0x2D || label.last == 0x2D) {
                return false
            }
        }

        // "4. If not CheckHyphens, the label must not begin with “xn--”."
        if !options.checkHyphens {
            if Processing.hasACEPrefix(label) {
                return false
            }
        }

        // "5. The label must not contain a U+002E ( . ) FULL STOP."
        if label.contains(0x2E) {
            return false
        }

        // "6. The label must not begin with a combining mark, that is: General_Category=Mark."
        if !isASCII && Lookup.contains(IDNATables.combiningMarks, label[0]) {
            return false
        }

        // "7. Each code point in the label must only have certain Status values according to Section 5"
        for codePoint in label {
            let status: Status
            if isASCII {
                // D6: tr46's ASCII rows are A–Z mapped and everything else valid.
                status = (0x41...0x5A).contains(codePoint) ? .mapped : .valid
            } else {
                status = Lookup.status(of: codePoint).0
            }
            if transitionalProcessing {
                // "For Transitional Processing (deprecated), each value must be valid."
                if status != .valid {
                    return false
                }
            } else if status != .valid && status != .deviation {
                // "For Nontransitional Processing, each value must be either valid or deviation."
                return false
            }
            // "In addition, if UseSTD3ASCIIRules=true and the code point is an ASCII code point (U+0000..U+007F), then it must
            // be a lowercase letter (a-z), a digit (0-9), or a hyphen-minus (U+002D). (Note: This excludes uppercase ASCII
            // A-Z which are mapped in UTS #46 and disallowed in IDNA2008.)"
            if options.useSTD3ASCIIRules && codePoint <= 0x7F {
                if !((0x61...0x7A).contains(codePoint) || (0x30...0x39).contains(codePoint) || codePoint == 0x2D) {
                    return false
                }
            }
        }

        // "8. If CheckJoiners, the label must satisify the ContextJ rules"
        // https://tools.ietf.org/html/rfc5892#appendix-A
        if options.checkJoiners && !isASCII {
            if !satisfiesContextJ(label) {
                return false
            }
        }

        // "9. If CheckBidi, and if the domain name is a Bidi domain name, then the label must satisfy..."
        // https://tools.ietf.org/html/rfc5893#section-2
        if options.checkBidi && isBidi {
            if !satisfiesBidi(label) {
                return false
            }
        }

        return true
    }

    // MARK: - Step 8, ContextJ

    /// tr46's CheckJoiners loop. A joiner right after a virama is allowed. Otherwise a ZWNJ is
    /// allowed if `regexes.validZWNJ` matches the segment from `last` up to, not including, the
    /// next ZWNJ after it. `last` moves past a ZWNJ only when that test passes, not when a virama
    /// allows it, so a segment can hold earlier ZWNJs (T7).
    ///
    /// Linear: each scan in `validZWNJ` stops at the neighbouring ZWNJ, and successive segments
    /// overlap only in a run that holds no ZWNJ.
    static func satisfiesContextJ(_ codePoints: [UInt32]) -> Bool {
        var last = 0
        for (i, ch) in codePoints.enumerated() {
            if ch == 0x200C || ch == 0x200D {
                if i > 0 {
                    if Lookup.contains(IDNATables.combiningClassVirama, codePoints[i - 1]) {
                        continue
                    }
                    if ch == 0x200C {
                        let next = codePoints[(i + 1)...].firstIndex(of: 0x200C)
                        let test = next.map { codePoints[last..<$0] } ?? codePoints[last...]
                        if validZWNJ(test) {
                            last = i + 1
                            continue
                        }
                    }
                }
                return false
            }
        }
        return true
    }

    /// `regexes.validZWNJ.test(segment)`, the unanchored `[#0][#1]*\u200C[#2]*[#3]`: some ZWNJ in
    /// the segment has a Joining_Type L or D letter before it and an R or D letter after it, with
    /// only Joining_Type T between. Every ZWNJ in the segment is tried, as the regex does, so an
    /// earlier ZWNJ that the virama rule let through can satisfy it, exactly as in tr46.
    ///
    /// No class holds U+200C (asserted by the generator), so each scan stops at a neighbouring ZWNJ.
    static func validZWNJ(_ segment: ArraySlice<UInt32>) -> Bool {
        for k in segment.indices where segment[k] == 0x200C {
            var before = false
            var m = k
            while m > segment.startIndex {
                m -= 1
                if Lookup.contains(IDNATables.validZWNJBefore, segment[m]) {
                    before = true
                    break
                }
                if !Lookup.contains(IDNATables.validZWNJTransparentBefore, segment[m]) {
                    break
                }
            }
            guard before else { continue }
            var n = k + 1
            while n < segment.endIndex {
                if Lookup.contains(IDNATables.validZWNJAfter, segment[n]) {
                    return true
                }
                if !Lookup.contains(IDNATables.validZWNJTransparentAfter, segment[n]) {
                    break
                }
                n += 1
            }
        }
        return false
    }

    // MARK: - Step 9, Bidi

    /// RFC 5893 section 2, as tr46 tests it with regexes.js.
    static func satisfiesBidi(_ label: [UInt32]) -> Bool {
        let rtl: Bool

        // 1
        if Lookup.contains(IDNATables.bidiS1LTR, label[0]) {
            rtl = false
        } else if Lookup.contains(IDNATables.bidiS1RTL, label[0]) {
            rtl = true
        } else {
            return false
        }

        if rtl {
            // 2-4
            if !label.allSatisfy({ Lookup.contains(IDNATables.bidiS2, $0) }) ||
                !endsWith(label, last: IDNATables.bidiS3Last, trailing: IDNATables.bidiS3Trailing) ||
                (label.contains { Lookup.contains(IDNATables.bidiS4EN, $0) } &&
                    label.contains { Lookup.contains(IDNATables.bidiS4AN, $0) }) {
                return false
            }
        } else if !label.allSatisfy({ Lookup.contains(IDNATables.bidiS5, $0) }) ||
                    !endsWith(label, last: IDNATables.bidiS6Last, trailing: IDNATables.bidiS6Trailing) {  // 5-6
            return false
        }

        return true
    }

    /// The unanchored `[last][trailing]*$`: scanning back from the end, a `last` member matches, a
    /// `trailing` member is skipped, and anything else, or the start of the label, doesn't match.
    static func endsWith(_ label: [UInt32], last: [UInt32], trailing: [UInt32]) -> Bool {
        var index = label.endIndex
        while index > label.startIndex {
            index -= 1
            if Lookup.contains(last, label[index]) {
                return true
            }
            if !Lookup.contains(trailing, label[index]) {
                return false
            }
        }
        return false
    }
}
