# Conformance

The test suites that tie the port to tr46 7.0.0, and their results.

## Overview

Every expected answer was checked against real tr46 7.0.0, loaded from its verified npm tarball,
when the test data was generated, and the Swift tests require all of them. The counts are from
`swift test` on macOS 27.0.1 with Xcode 27.0 (Swift 6.4).

| Suite | Result |
| --- | --- |
| Unicode IdnaTestV2 18.0.0, read strictly | 6,394 of 6,396 lines; toUnicode 6,394/6,394, toASCII nontransitional 6,394/6,394, toASCII transitional 6,394/6,394 |
| IdnaTestV2 with `.foundation` | 6,180/6,180 lines with no character newer than Unicode 14.0 |
| Unicode NormalizationTest 18.0.0 | 20,171/20,171 lines; 1,094,910/1,094,910 other code points unchanged |
| web-platform-tests at commit 13748c3 | toascii.json 61/61; IdnaTestV2.json 1,680/1,680 |
| tr46's std3ASCIIRules and url-host-parsing tests | 106 cases; 127 × 2 assertions |
| GeoSpoof fixture | 3,769/3,769 with ``TR46/TR46/Normalization/bundled`` and with `.foundation` |
| Differential against tr46 on Node 24.12.0 | 9,732 inputs; `toASCII` 1,245,696/1,245,696; `toUnicode` 622,848/622,848 |
| Differential with `.foundation` | 9,216 inputs × 4 option combinations, 0 differences |
| Punycode | RFC 3492 samples A–S in both directions |

## IdnaTestV2

Unicode's `IdnaTestV2.txt` for 18.0.0 has 6,396 test lines. Two hold a lone surrogate, which a
Swift `String` can't represent, and are skipped; the file's header allows that. Each remaining
line is checked three ways: toUnicode, toASCII with nontransitional processing, and toASCII with
transitional processing, all with every check on, as tr46's own `test/unicode.js` does.

The reading is stricter than tr46's harness in three ways: a blank status column inherits as the
file documents, `hadError` is checked on every line, and toUnicode's domain is compared on error
lines too. tr46 7.0.0 passes this reading on all 6,396 lines.

## web-platform-tests

The URL Standard's IDNA tests, `url/resources/toascii.json` and `url/resources/IdnaTestV2.json`,
at commit `13748c36fdf9dd77cd0b34dd6b244256b365ea60`, the commit tr46 7.0.0's tests use. Cases are
selected by tr46's `test/toascii.js` rules, and run with its options (``TR46/TR46/Options/checkBidi``
and ``TR46/TR46/Options/checkJoiners`` on): 61 from toascii.json and 1,680 from IdnaTestV2.json.

## Differential testing

`differential.json` holds tr46's own answers for 9,732 inputs under every option combination: 128
for ``TR46/TR46/toASCII(_:options:)`` and 64 for ``TR46/TR46/toUnicode(_:options:)``, which ignores
``TR46/TR46/Options/verifyDNSLength``. The inputs are:

- 6,281 IdnaTestV2 sources
- 80 web-platform-tests inputs not already among them, including those tr46's harness skips
- 371 curated inputs covering each behaviour in <doc:BehaviourFromJavaScript>, Punycode overflow,
  DNS length edges, STD3, hyphens, transitional mapping, bidi, NFC, emoji sequences and the full
  stop variants
- 3,000 fuzzed inputs from mulberry32 with seed `0x74723436`

121 inputs are left out because they hold a character that Unicode 18.0.0 assigns and Node 24's
Unicode 16.0 doesn't; there Node's NFC and Unicode 18's could legitimately differ. Characters
unassigned in both stay in, because both versions treat them the same.

## The GeoSpoof fixture

3,769 answers recorded from the GeoSpoof browser extension's `hostToASCII`, which calls tr46 7.0.0
with the URL Standard's options and reads `""` as a failure: 59 curated inputs and 3,710 from
IdnaTestV2. They pass with both normalization modes.
