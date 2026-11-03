// Ported from tr46 7.0.0 index.js (mapChars, isBidiDomain, processing).
// Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

/// UTS #46 section 4, Processing, as tr46 implements it. `TR46.toASCII` and `TR46.toUnicode` both
/// start here, as tr46's do.
///
/// Every function takes `asciiFastPath`, true outside the tests. It replaces a table lookup or NFC
/// with an equivalent table-free branch for ASCII (D6), and each branch rests on an assertion in
/// Scripts/generate-tables.mjs: in tr46's mapping table, A–Z are mapped to the lower-case letter
/// and every other ASCII code point is valid, with no ASCII deviation; ASCII is NFC_QC=Yes with
/// combining class 0; and no ASCII code point is in combiningMarks, combiningClassVirama, the
/// validZWNJ classes or bidiDomain. FastPathTests checks both settings give the same result.
enum Processing {
    /// tr46's `mapChars(domainName, { transitionalProcessing })`: UTS #46 step 1, Map.
    static func mapChars(_ domainName: String, transitionalProcessing: Bool, asciiFastPath: Bool = true) -> [UInt32] {
        var processed: [UInt32] = []
        processed.reserveCapacity(domainName.utf8.count)

        for scalar in domainName.unicodeScalars {
            let ch = scalar.value
            if asciiFastPath && ch < 0x80 {
                // D6: A–Z are mapped to a–z, and every other ASCII code point is valid.
                processed.append((0x41...0x5A).contains(ch) ? ch + 0x20 : ch)
                continue
            }
            let (status, mapping) = Lookup.status(of: ch)

            switch status {
            case .disallowed:
                processed.append(ch)
            case .ignored:
                break
            case .mapped:
                if transitionalProcessing && ch == 0x1E9E {  // ch === "ẞ"
                    processed.append(contentsOf: [0x73, 0x73])  // "ss"
                } else {
                    processed.append(contentsOf: mapping)
                }
            case .deviation:
                if transitionalProcessing {
                    processed.append(contentsOf: mapping)
                } else {
                    processed.append(ch)
                }
            case .valid:
                processed.append(ch)
            }
        }

        return processed
    }

    /// tr46's `isBidiDomain(labels)`: whether any label holds a code point of Bidi_Class R, AL or
    /// AN. An `xn--` label counts by what it decodes to, and as empty if it doesn't decode (T11).
    ///
    /// tr46 joins the labels with "." and tests the joined string once. A "." isn't in the class,
    /// and it separates the labels, so it can't pair surrogates across them; testing label by
    /// label, code point by code point, gives the same answer.
    static func isBidiDomain(_ labels: [[UInt32]], asciiFastPath: Bool = true) -> Bool {
        labels.contains { label in
            let domain: [UInt32]
            if hasACEPrefix(label) {
                domain = Punycode.decode(Array(label.dropFirst(4))).flatMap(JSString.fromCodePoints) ?? []
            } else {
                // D6: bidiDomain holds no ASCII.
                if asciiFastPath && !JSString.containsNonASCII(label) { return false }
                domain = label
            }
            return domain.contains { Lookup.contains(IDNATables.bidiDomain, $0) }
        }
    }

    /// tr46's `processing(domainName, options)`: UTS #46 section 4, steps 1 to 4. Returns the
    /// labels, decoded where tr46 decodes them, and tr46's error flag.
    ///
    /// The error flag is sticky, and the loop carries on after it: later labels are still decoded
    /// but no longer validated (T1, D14). toUnicode's output needs the decoded labels; toASCII
    /// returns nil whenever the flag is set, so nothing after the first error changes its result.
    static func process(_ domainName: String, options: TR46.Options, asciiFastPath: Bool = true) -> (labels: [[UInt32]], error: Bool) {
        let normalizer = Normalizer(mode: options.normalization)

        // 1. Map.
        var string = mapChars(domainName, transitionalProcessing: options.transitionalProcessing, asciiFastPath: asciiFastPath)

        // 2. Normalize.
        // D6: an all-ASCII string is already in NFC.
        if !(asciiFastPath && !JSString.containsNonASCII(string)) {
            string = normalizer.nfc(string)
        }

        // 3. Break.
        // split(".") keeps empty labels: "" is one empty label and "a." is "a" and "" (J9).
        var labels = string.split(separator: 0x2E, omittingEmptySubsequences: false).map(Array.init)
        let isBidi = isBidiDomain(labels, asciiFastPath: asciiFastPath)

        // 4. Convert/Validate.
        var error = false
        for i in labels.indices {
            var label = labels[i]
            var transitionalProcessingForThisLabel = options.transitionalProcessing
            if hasACEPrefix(label) {
                if JSString.containsNonASCII(label) {
                    error = true
                    continue
                }

                if let decoded = Punycode.decode(Array(label.dropFirst(4))).flatMap(JSString.fromCodePoints) {
                    label = decoded
                } else if !options.ignoreInvalidPunycode {
                    error = true
                    continue
                }
                labels[i] = label

                if label.isEmpty || !JSString.containsNonASCII(label) {
                    error = true
                }

                transitionalProcessingForThisLabel = false
            }

            // No need to validate if we already know there is an error.
            if error {
                continue
            }
            let validation = Validation.validateLabel(
                label,
                options: options,
                transitionalProcessing: transitionalProcessingForThisLabel,
                isBidi: isBidi,
                normalizer: normalizer,
                asciiFastPath: asciiFastPath
            )
            if !validation {
                error = true
            }
        }

        return (labels, error)
    }

    /// `label.startsWith("xn--")`. Labels are compared after mapping, which lower-cases `XN--`.
    static func hasACEPrefix(_ label: [UInt32]) -> Bool {
        label.starts(with: [0x78, 0x6E, 0x2D, 0x2D])
    }
}
