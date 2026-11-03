// Ported from tr46 7.0.0 index.js (toASCII, toUnicode).
// Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

/// A Swift port of tr46, jsdom's implementation of Unicode IDNA Compatibility Processing (UTS #46).
public enum TR46 {
    /// The tr46 npm release this package ports.
    public static let upstreamVersion = "7.0.0"

    /// The Unicode version of tr46's data, and of the NFC data bundled with this package.
    public static let unicodeVersion = "18.0.0"

    /// UTS #46 ToASCII, as tr46's `toASCII(domainName, options)`.
    ///
    /// Returns nil exactly where tr46 returns `null`, and the same string everywhere else,
    /// including `""` for an input such as `""` or `"\u{00AD}"` that processes to nothing. With
    /// ``Options/verifyDNSLength`` on, `""` is refused instead.
    ///
    /// ```swift
    /// TR46.toASCII("Bücher.example")                            // "xn--bcher-kva.example"
    /// TR46.toASCII("xn--zz.com")                                // nil
    /// TR46.toASCII("faß.de", options: .init(transitionalProcessing: true))  // "fass.de"
    /// ```
    public static func toASCII(_ domainName: String, options: Options = Options()) -> String? {
        let result = Processing.process(domainName, options: options)
        // tr46 carries on to the end and returns null if the flag is set. Nothing below can clear
        // it, so stopping here gives the same answer.
        if result.error {
            return nil
        }

        // tr46 splits `result.string`, the labels joined by ".", on "." again. That gives back the
        // same labels: none holds a U+002E. A label that wasn't decoded was split on it, and a
        // decoded one holds the basic code points of such a label plus inserted values of at
        // least 0x80 (Punycode's n starts at 0x80 and never decreases).
        var labels: [[UInt8]] = []
        labels.reserveCapacity(result.labels.count)
        for label in result.labels {
            if JSString.containsNonASCII(label) {
                guard let encoded = Punycode.encode(label) else {
                    return nil  // result.error = true
                }
                labels.append(Array("xn--".utf8) + encoded)
            } else {
                labels.append(label.map { UInt8($0) })
            }
        }

        // Every label is ASCII now, so JavaScript's .length, in UTF-16 units, is the byte count (J6).
        if options.verifyDNSLength {
            let total = labels.reduce(labels.count - 1) { $0 + $1.count }
            if total > 253 || total == 0 {
                return nil
            }

            for label in labels {
                if label.count > 63 || label.isEmpty {
                    return nil
                }
            }
        }

        return String(decoding: Array(labels.joined(separator: [0x2E])), as: UTF8.self)
    }

    /// UTS #46 ToUnicode, as tr46's `toUnicode(domainName, options)`: the processed domain, and
    /// whether any label failed.
    ///
    /// As in tr46, the domain is returned even when `hadError` is true, with every `xn--` label
    /// that decodes decoded, including the ones after the first error.
    /// ``Options/verifyDNSLength`` is ignored.
    ///
    /// A label can decode to a lone surrogate, which tr46 returns as it is in a JavaScript string,
    /// always with an error. A Swift `String` can't hold one, so it is replaced by U+FFFD, as
    /// JavaScript's `toWellFormed()` does: tr46's `{domain: "\uD83D.com", error: true}` for
    /// `"xn--8c9b.com"` is `("\u{FFFD}.com", true)` here.
    ///
    /// ```swift
    /// TR46.toUnicode("xn--mnchen-3ya.de")        // ("münchen.de", false)
    /// TR46.toUnicode("xn--zz.xn--mnchen-3ya.de") // ("xn--zz.münchen.de", true)
    /// ```
    public static func toUnicode(_ domainName: String, options: Options = Options()) -> (domain: String, hadError: Bool) {
        let result = Processing.process(domainName, options: options)
        return (JSString.wellFormedString(joining: result.labels), result.error)
    }
}
