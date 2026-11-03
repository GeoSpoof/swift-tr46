// The options of tr46 7.0.0's toASCII and toUnicode (index.js), plus the choice of NFC data.
// tr46 7.0.0 index.js, Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

extension TR46 {
    /// The options of tr46's `toASCII` and `toUnicode`, under the same names and with the same
    /// defaults.
    ///
    /// Every Boolean defaults to `false`, as in tr46's README and `index.js`. The defaults are not
    /// the WHATWG URL Standard's: its "domain to ASCII" with `beStrict` false sets
    /// ``checkBidi`` and ``checkJoiners`` to `true` and leaves the rest `false`.
    ///
    /// ```swift
    /// let url = TR46.Options(checkBidi: true, checkJoiners: true)
    /// TR46.toASCII("münchen.de", options: url)   // "xn--mnchen-3ya.de"
    /// ```
    public struct Options: Sendable, Hashable {
        /// Refuse a label with U+002D HYPHEN-MINUS in both its third and fourth positions, or at
        /// its start or end. UTS #46's `CheckHyphens`.
        ///
        /// The third and fourth positions count code points, not UTF-16 units, as tr46 does. When
        /// this is `false`, a label that begins with `xn--` after processing is refused instead.
        public var checkHyphens: Bool

        /// Apply the RFC 5893 bidi rules to every label of a domain that holds a right-to-left
        /// character (Bidi_Class R, AL or AN) in any label. UTS #46's `CheckBidi`.
        public var checkBidi: Bool

        /// Apply the RFC 5892 Appendix A ContextJ rules to U+200C ZERO WIDTH NON-JOINER and U+200D
        /// ZERO WIDTH JOINER. UTS #46's `CheckJoiners`.
        public var checkJoiners: Bool

        /// Allow only `a`–`z`, `0`–`9` and `-` among the ASCII code points of a label (upper-case
        /// letters are mapped to lower case before this check). UTS #46's `UseSTD3ASCIIRules`.
        public var useSTD3ASCIIRules: Bool

        /// Map the deviation characters, ß to "ss", ς to "σ", and ZWNJ and ZWJ to nothing, and map
        /// U+1E9E LATIN CAPITAL LETTER SHARP S to "ss". UTS #46's `Transitional_Processing`, which
        /// UTS #46 deprecates.
        ///
        /// It never applies to a label decoded from Punycode, which is always processed
        /// nontransitionally.
        public var transitionalProcessing: Bool

        /// Refuse a result whose length is 0 or above 253, or that has a label of length 0 or above
        /// 63, counting the ASCII result. UTS #46's `VerifyDnsLength`.
        ///
        /// Only ``TR46/toASCII(_:options:)`` reads it. ``TR46/toUnicode(_:options:)`` ignores it,
        /// as tr46 does.
        public var verifyDNSLength: Bool

        /// Keep going when an `xn--` label is not valid Punycode, instead of failing at once. UTS
        /// #46's `IgnoreInvalidPunycode`.
        ///
        /// In tr46 7.0.0 this changes no result. A label that fails to decode stays as its ASCII
        /// `xn--` form, and the very next check, that a decoded label holds a non-ASCII code point,
        /// sets the error anyway. This package ports that as written.
        public var ignoreInvalidPunycode: Bool

        /// Which NFC data the two normalization steps use. tr46 calls JavaScript's
        /// `String.prototype.normalize("NFC")`; ``Normalization/bundled`` gives the Unicode 18.0.0
        /// answer on every platform.
        public var normalization: Normalization

        /// Options with every check off, the defaults of tr46's `toASCII` and `toUnicode`, unless
        /// given here.
        public init(
            checkHyphens: Bool = false,
            checkBidi: Bool = false,
            checkJoiners: Bool = false,
            useSTD3ASCIIRules: Bool = false,
            transitionalProcessing: Bool = false,
            verifyDNSLength: Bool = false,
            ignoreInvalidPunycode: Bool = false,
            normalization: Normalization = .bundled
        ) {
            self.checkHyphens = checkHyphens
            self.checkBidi = checkBidi
            self.checkJoiners = checkJoiners
            self.useSTD3ASCIIRules = useSTD3ASCIIRules
            self.transitionalProcessing = transitionalProcessing
            self.verifyDNSLength = verifyDNSLength
            self.ignoreInvalidPunycode = ignoreInvalidPunycode
            self.normalization = normalization
        }
    }

    /// The Unicode Normalization Form C implementation behind tr46's two NFC steps: normalizing the
    /// mapped domain, and checking that each label is already in NFC.
    public enum Normalization: Sendable, Hashable {
        /// The Unicode 18.0.0 NFC compiled into this package, so the answer is the same on every OS
        /// and platform. This is the default.
        case bundled

        #if canImport(Darwin)
        /// Foundation's `precomposedStringWithCanonicalMapping`, which uses the OS's own Unicode
        /// data. Only on Apple platforms.
        ///
        /// For apps that have to agree with tr46 running in a browser on the same device. NFC is
        /// stable for assigned characters, so this can differ from ``bundled`` only on characters
        /// the OS's Unicode version doesn't assign, or where the OS's normalization has a defect.
        case foundation
        #endif
    }
}
