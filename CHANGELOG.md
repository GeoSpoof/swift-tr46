# Changelog

The major and minor version match the tr46 release being ported; the patch number belongs to this
package. See the README's Versioning section.

## 7.0.0

First release. A Swift port of [tr46](https://github.com/jsdom/tr46) 7.0.0, whose data is Unicode
18.0.0, and of the Punycode encoder and decoder from
[punycode.js](https://github.com/mathiasbynens/punycode.js) 2.3.1.

### API

- `TR46.toASCII(_:options:) -> String?`: `nil` exactly where tr46 returns `null`.
- `TR46.toUnicode(_:options:) -> (domain: String, hadError: Bool)`.
- `TR46.Options`, with tr46's seven options under its names and defaults (`checkHyphens`,
  `checkBidi`, `checkJoiners`, `useSTD3ASCIIRules`, `transitionalProcessing`, `verifyDNSLength`,
  `ignoreInvalidPunycode`, all `false`), plus `normalization`.
- `TR46.Normalization`, a `Sendable`, `Hashable` struct with two static properties: `.bundled`,
  Unicode 18.0.0 NFC tables compiled into the package (the default), and on Apple platforms
  `.foundation`, which uses Foundation's `precomposedStringWithCanonicalMapping`. It is a struct
  rather than an enum so that a later release can add a mode without a source break, which the
  versioning policy could otherwise only ship with a new tr46 major. A `switch` over it needs a
  `default:` case. `.foundation` takes Foundation's time, which is quadratic in the length of a
  run of combining marks; bound untrusted input in that mode.
- `TR46.upstreamVersion` (`"7.0.0"`) and `TR46.unicodeVersion` (`"18.0.0"`).

Every type is `Sendable`. There are no dependencies.

### Platforms

Swift 6.0 or later, on Apple platforms and Linux. `Package.swift` declares no `platforms:`, so the
deployment targets are the toolchain's minimums. CI covers Xcode 16.0, the newest Xcode on GitHub's
macOS 26 image, Swift 6.0.3 and 6.4.2 on Linux, and an iOS Simulator build.

### Conformance

- Unicode IdnaTestV2 18.0.0, read strictly: 6,394 of 6,396 lines for toUnicode, toASCII
  nontransitional and toASCII transitional (2 lines hold a lone surrogate and are skipped).
- Unicode NormalizationTest 18.0.0: 20,171/20,171 lines, and 1,094,910/1,094,910 other code points.
- web-platform-tests at tr46's pinned commit: toascii.json 61/61, IdnaTestV2.json 1,680/1,680.
- The GeoSpoof fixture: 3,769/3,769, with both normalization modes.
- Differential against tr46 7.0.0 on Node 24.12.0: 9,734 inputs under all 128 `toASCII` and 64
  `toUnicode` option combinations, 1,245,952 and 622,976 results, all equal.

### Differences from tr46

- A lone surrogate in `toUnicode`'s output becomes U+FFFD, always with `hadError == true`.
- Inputs holding a lone surrogate can't be represented as a Swift `String`.
- Decoding has no length limit; tr46's `String.fromCodePoint(...)` throws above about 120,000 code
  points on Node 24.12.0.
- Punycode above 1,024 code points runs in O(n log n) rather than O(n²), with the same results.

### Not included

- A throwing variant that reports which rule failed. tr46 reports one Boolean, so there is nothing
  to test detailed errors against. It may come in a later release.
