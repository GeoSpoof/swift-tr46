# swift-tr46

A Swift port of [tr46](https://github.com/jsdom/tr46), jsdom's implementation of
[Unicode IDNA Compatibility Processing (UTS #46)](https://www.unicode.org/reports/tr46/),
together with the Punycode encoder and decoder from
[punycode.js](https://github.com/mathiasbynens/punycode.js).

It converts domain names between their Unicode and ASCII (`xn--`) forms with `toASCII` and
`toUnicode`, and gives the same result as tr46 7.0.0 for every input and every combination of
options, quirks included.

## Why this package

- **Exact tr46 output.** An app that has to agree with jsdom, whatwg-url or a browser extension
  that uses tr46 needs the same answer for the same input, including where tr46
  differs from a strict reading of UTS #46. This package is tested against tr46 itself on 9,732
  inputs under all 128 `toASCII` and 64 `toUnicode` option combinations (see
  [Conformance](#conformance)).
- **No dependencies.** The library uses only the Swift standard library, plus Foundation on Apple
  platforms for the optional `.foundation` normalization mode.
- **Swift 6.0 or later**, in Swift 6 language mode with strict concurrency.
- **Apple platforms and Linux.**

Another Swift UTS #46 implementation is [swift-dns/swift-idna](https://github.com/swift-dns/swift-idna),
which targets Unicode 18 and is written for speed. As of November 2026 its newest tag is
1.0.0-beta.25, a prerelease, and it has no stable release. It needs swift-tools-version 6.3,
depends on swift-collections and swift-highway, includes generated C, and is Apache-2.0 licensed.
Its README lists `checkBidi`, `checkJoiners` and `transitionalProcessing` as not supported, and its
source documents `checkBidi` and `checkJoiners` as no-ops. Use it if those trade-offs suit you and
you don't need tr46's exact output.

## Status

The first release, 7.0.0, ports tr46 7.0.0, whose data is Unicode 18.0.0, and punycode.js
2.3.1. There is no throwing variant that reports which rule failed; see
[Differences from tr46](#differences-from-tr46).

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/GeoSpoof/swift-tr46", exact: "7.0.0"),
    // or: .package(url: "https://github.com/GeoSpoof/swift-tr46", from: "7.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [.product(name: "TR46", package: "swift-tr46")]),
]
```

Pin with `exact:` if your output must track one tr46 release. See [Versioning](#versioning).

## Usage

```swift
import TR46

TR46.toASCII("Bücher.example")              // "xn--bcher-kva.example"
TR46.toASCII("xn--zz.com")                  // nil: not valid Punycode

TR46.toUnicode("xn--mnchen-3ya.de")         // (domain: "münchen.de", hadError: false)
TR46.toUnicode("xn--zz.xn--mnchen-3ya.de")  // (domain: "xn--zz.münchen.de", hadError: true)
```

`toASCII` returns `nil` exactly where tr46 returns `null`. `toUnicode` always returns a domain,
with every label that decodes decoded, and says whether any label failed.

### The WHATWG URL Standard's "domain to ASCII"

tr46's defaults turn every check off. The URL Standard's
[domain to ASCII](https://url.spec.whatwg.org/#concept-domain-to-ascii), with `beStrict` false, as
browsers and whatwg-url use it, turns on `checkBidi` and `checkJoiners` and leaves the rest off:

```swift
let url = TR46.Options(checkBidi: true, checkJoiners: true)

TR46.toASCII("EXAMPLE.münchen.de", options: url)   // "example.xn--mnchen-3ya.de"
TR46.toASCII("\u{0628}\u{200C}a", options: url)    // nil: the ZWNJ fails ContextJ
```

The URL Standard also treats an empty result as a failure, so check for `""` as well as `nil`.
With `beStrict` true, it also sets `useSTD3ASCIIRules` and `verifyDNSLength`.

### Options

Every Boolean defaults to `false`, as in tr46's README and `index.js`.

| Option | Default | What it does | UTS #46 flag |
| --- | --- | --- | --- |
| `checkHyphens` | `false` | Refuses a label with `-` in both its third and fourth positions, counted in code points, or at its start or end. When off, a label that starts with `xn--` after processing is refused instead. | `CheckHyphens` |
| `checkBidi` | `false` | Applies the RFC 5893 bidi rules to every label, when any label of the domain holds a right-to-left character. | `CheckBidi` |
| `checkJoiners` | `false` | Applies the RFC 5892 ContextJ rules to U+200C ZERO WIDTH NON-JOINER and U+200D ZERO WIDTH JOINER. | `CheckJoiners` |
| `useSTD3ASCIIRules` | `false` | Allows only `a`–`z`, `0`–`9` and `-` among a label's ASCII characters. | `UseSTD3ASCIIRules` |
| `transitionalProcessing` | `false` | Maps ß to `ss`, ς to `σ`, ZWNJ and ZWJ to nothing, and U+1E9E ẞ to `ss`. Never applied to a label decoded from Punycode. UTS #46 deprecates it. | `Transitional_Processing` |
| `verifyDNSLength` | `false` | `toASCII` only: refuses an empty result, a result longer than 253, and a label that is empty or longer than 63. `toUnicode` ignores it, as tr46 does. | `VerifyDnsLength` |
| `ignoreInvalidPunycode` | `false` | Changes no result in tr46 7.0.0: a label that fails to decode is refused by the next check anyway. Ported as written. | `IgnoreInvalidPunycode` |
| `normalization` | `.bundled` | Which NFC implementation the two normalization steps use. See below. | none |

```swift
TR46.toASCII("faß.de")                                                 // "xn--fa-hia.de"
TR46.toASCII("faß.de", options: .init(transitionalProcessing: true))   // "fass.de"
TR46.toASCII("a_b.example", options: .init(useSTD3ASCIIRules: true))   // nil
TR46.toASCII("example.com.", options: .init(verifyDNSLength: true))    // nil: empty last label
```

## Normalization modes

UTS #46 normalizes to NFC twice: the whole mapped domain, and a check that each label is already
in NFC. tr46 calls JavaScript's `String.prototype.normalize("NFC")` for both. Swift has no public
normalization API: in the Swift 6.4 standard library's interface the only normalization symbols are
underscored (`String._nfcCodeUnits`, `String._withNFCCodeUnits`), and the 2024
[Unicode Normalization pitch](https://forums.swift.org/t/pitch-unicode-normalization/73240) did not
become API. On Apple platforms the standard library ships with the OS, so its Unicode data would
change with the OS version anyway. This package therefore carries its own NFC.

- **`.bundled`** (the default) uses Unicode 18.0.0 NFC tables compiled into the package, so the
  answer is the same on every OS and platform.
- **`.foundation`** uses Foundation's `precomposedStringWithCanonicalMapping`, which uses the OS's
  normalization data. It exists for apps that have to agree with tr46 running in a browser on the
  same device. GeoSpoof uses it because its Safari extension runs tr46, and tr46 calls
  JavaScriptCore's `normalize("NFC")` on the same device.

How far apart the two can be:

- Nothing guarantees that JavaScriptCore and Foundation use the same Unicode version. On macOS
  13–15, Safari updates ship their own WebKit and JavaScriptCore, separately from the OS.
- NFC is stable for assigned characters under Unicode's normalization stability policy, so two
  correct implementations can differ only on characters that one data version assigns and the other
  doesn't.
- `.bundled` gives the Unicode 18.0.0 answer everywhere. tr46 itself normalizes with whatever engine
  runs it, so for characters newer than that engine's Unicode version, tr46's result depends on the
  engine.
- Foundation's NFC is not always correct. On macOS 27.0.1 it gives the wrong NFC for 4
  NormalizationTest inputs: U+1100 U+AC00 U+11A8, the same with a second U+11A8, U+1100 U+1161
  U+11A7, and U+0CCA U+0CD5. It leaves a precomposed Hangul LV syllable before a trailing consonant
  uncomposed (even U+AC00 U+11A8 alone), drops the U+11A7, and leaves U+0CCA U+0CD5 uncomposed
  instead of returning U+0CCB. The bundled NFC, ICU and NormalizationTest agree on the right
  answer. So `.foundation` can differ from tr46 running on JavaScriptCore, which uses ICU, for a
  domain holding one of these sequences. None of them occurs in the IdnaTestV2, GeoSpoof or
  differential inputs that the `.foundation` tests run.

`.foundation` exists only on Apple platforms (`#if canImport(Darwin)`). On Linux,
`precomposedStringWithCanonicalMapping` comes from swift-corelibs-foundation with its own tables,
so there is no JavaScript engine on the same device for it to match, and supporting it would make
the library import Foundation on Linux, which pulls ICU data into static server binaries. On Linux
the library needs only the standard library.

## Conformance

Every expected answer below was checked against real tr46 7.0.0 when the test data was generated,
and the Swift tests require all of them. Counts are from `swift test` on macOS 27.0.1 with Xcode
27.0 (Swift 6.4):

| Suite | Result |
| --- | --- |
| Unicode IdnaTestV2 18.0.0, read strictly | 6,394 of 6,396 lines (2 hold a lone surrogate and are skipped); toUnicode 6,394/6,394, toASCII nontransitional 6,394/6,394, toASCII transitional 6,394/6,394 |
| IdnaTestV2 with `.foundation` | 6,180/6,180 lines with no character newer than Unicode 14.0 |
| Unicode NormalizationTest 18.0.0 (bundled NFC) | 20,171/20,171 lines; every other code point, 1,094,910/1,094,910, is unchanged by NFC |
| web-platform-tests at tr46's pin (13748c3) | toascii.json 61/61; IdnaTestV2.json 1,680/1,680 |
| tr46's own std3ASCIIRules and url-host-parsing tests | 106 cases; 127 × 2 assertions |
| GeoSpoof fixture (tr46 7.0.0 answers recorded by a browser extension) | 3,769/3,769 with `.bundled`, 3,769/3,769 with `.foundation` |
| Differential against tr46 7.0.0 on Node 24.12.0 | 9,732 inputs × 128 `toASCII` combinations = 1,245,696/1,245,696; × 64 `toUnicode` combinations = 622,848/622,848 |
| Differential with `.foundation` | 9,216 inputs × 4 combinations, 0 differences |
| Punycode | RFC 3492 samples A–S both ways; the two code paths agree on 2,000 random inputs of up to 2,999 code points |

"Strictly" means a blank status column inherits as the file documents, `hadError` is checked on
every line, and toUnicode's domain is compared on error lines too. tr46's own harness is looser on
all three; tr46 7.0.0 passes the strict reading.

The differential inputs are every IdnaTestV2 source and every WPT input that a Swift string can
hold (including the WPT inputs tr46's harness skips), with duplicates removed, plus 371 curated
cases and 3,000 fuzzed ones (mulberry32, seed `0x74723436`). 121 inputs are left out because they hold a character that Unicode 18.0.0 assigns and Node 24's
Unicode 16.0 doesn't, where the two NFCs could legitimately differ.

## Differences from tr46

- **A lone surrogate in `toUnicode`'s output becomes U+FFFD.** A Punycode label can decode to an
  unpaired surrogate, which tr46 returns inside a JavaScript string. A Swift `String` can't hold
  one, so it is replaced as `String.prototype.toWellFormed()` does: tr46's
  `{domain: "\uD83D.com", error: true}` for `xn--8c9b.com` is `("\u{FFFD}.com", true)` here. This
  only ever happens with `hadError == true`.
- **Inputs holding a lone surrogate can't be passed in**, for the same reason. Two IdnaTestV2 lines
  and two WPT inputs are skipped because of it.
- **No length limit on decoding.** tr46 builds a decoded label with
  `String.fromCodePoint(...output)`, which throws once the label passes the engine's argument limit
  (between 120,000 and 125,000 code points on Node 24.12.0). Swift decodes any length.
- **No throwing variant.** tr46 reports one Boolean. It carries on after the first error and
  doesn't say which rule failed, so there is nothing to test a detailed error against. This may
  come in a later release.

[Behaviour from JavaScript](Sources/TR46/Documentation.docc/BehaviourFromJavaScript.md) lists the
JavaScript behaviours the port reproduces, such as decoded surrogate halves re-pairing, and tr46's
control-flow quirks.

## Platforms

`Package.swift` declares no `platforms:`. The library uses only standard-library API, plus
Foundation's `precomposedStringWithCanonicalMapping` (macOS 10.2, iOS 2.0) on Apple platforms, so
the deployment targets are the toolchain's own minimums. With Xcode 27 those are macOS 12.0,
iOS 15.0, tvOS 15.0, watchOS 9.0 and visionOS 1.0; SwiftPM 6.0's defaults are lower. A declared
floor would only produce deprecation warnings on newer Xcode.

Linux is supported with Swift 6.0 or later.

CI builds and tests with Xcode 16.0 (Swift 6.0), the newest Xcode on GitHub's macOS 26 image,
and the `swift:6.0.3-noble` and `swift:6.4.2-noble` Linux images. It also builds for the iOS
Simulator. The package was developed with Xcode 27.0 (Swift 6.4), where it also builds for the
tvOS, watchOS and visionOS simulators and for watchOS devices (arm64_32, whose `Int` is 32 bits;
Punycode's state is `Int64` for this reason).

## Performance

- Mapping, splitting and joining are linear, with a binary search of the mapping table per
  non-ASCII code point.
- NFC is linear, plus O(k log k) to reorder a run of k combining marks.
- Label validation is linear.
- Punycode: punycode.js is O(n²) in the label length. Up to 1,024 code points this package runs the
  same algorithm line for line; above that it runs the same arithmetic in the same order with a
  Fenwick tree, in O(n log n). Quadratic Punycode decoding is a known denial-of-service class
  (CVE-2022-45061 in CPython).

`swift run -c release --package-path Benchmarks TR46Benchmark` on one Apple Silicon Mac, release
build; runs vary by about 20% with machine load:

| Workload | ops/s | ns/op |
| --- | ---: | ---: |
| `toASCII`, ASCII hostnames | 931,567 | 1,073.5 |
| `toASCII`, IDN hostnames (`münchen.de`, `пример.рф`, `例え.jp`) | 487,838 | 2,049.9 |
| `toUnicode`, their A-labels | 419,253 | 2,385.2 |
| `toASCII`, one 64,000-code-point label | 64 | 15,559,218.5 |
| `toUnicode`, its A-label | 50 | 20,084,578.3 |

The test suite's performance tests run in debug with a one-minute limit each: encoding and decoding
a 1,000,000-code-point label takes 3.3 s on the same machine.

## Security notes

- **IDNA is not a homograph defence by itself.** This package implements UTS #46 and makes no
  judgement about confusable or mixed-script names: `p\u{0430}ypal.com`, with a Cyrillic `а`,
  converts to `xn--pypal-4ve.com` without error, even with every check on. For confusables, see
  [UTS #39](https://www.unicode.org/reports/tr39/).
- **The defaults allow a lot.** With every check off, as tr46's defaults are, hyphen placement,
  bidi, joiners and STD3 characters are not checked. Choose the options your protocol needs; for
  URLs, see [above](#the-whatwg-url-standards-domain-to-ascii).
- **Bound untrusted input.** `verifyDNSLength` is off by default, and without it there is no length
  limit. The work is linear or O(n log n) in the input, but a caller that accepts arbitrary input
  should cap its length first.
- **Quirks match tr46.** For example `ignoreInvalidPunycode` changes nothing, and the ContextJ check
  accepts a second ZWNJ because an earlier one in the same label was allowed. If you need a
  different reading of UTS #46, this is not the package for it.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Versioning

The major and minor version match the tr46 release being ported. The patch number belongs to this
package: a fix to the port and a tr46 patch release both ship as the next patch, so a version
number never refers to two different sets of code. The ported tr46 version is available in code as
`TR46.upstreamVersion`, and the Unicode version of the data as `TR46.unicodeVersion`.

Release tags are plain version numbers, such as `7.0.0`. Changes are listed in
[CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing, regenerating the tables and updating
to a new tr46 or Unicode version.

## Credits

- [tr46](https://github.com/jsdom/tr46), by Sebastian Mayr and contributors, part of
  [jsdom](https://github.com/jsdom). The port follows its `index.js` step by step, and the IDNA
  tables are re-encoded from its data.
- [punycode.js](https://github.com/mathiasbynens/punycode.js), by Mathias Bynens.
- The [Unicode Character Database](https://www.unicode.org/ucd/), and Unicode's IdnaTestV2 and
  NormalizationTest data.
- [web-platform-tests](https://github.com/web-platform-tests/wpt), for the URL Standard's IDNA tests.

## License

MIT, see [LICENSE](LICENSE), which carries the copyright notices of tr46 and punycode.js. The
generated Unicode data and the test data have their own notices: see [NOTICE](NOTICE).
