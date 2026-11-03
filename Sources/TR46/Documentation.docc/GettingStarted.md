# Getting started

Add the package, convert a domain name, and choose options for your protocol.

## Add the package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/GeoSpoof/swift-tr46", exact: "7.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [.product(name: "TR46", package: "swift-tr46")]),
]
```

The major and minor version match the tr46 release being ported, and the patch number belongs to
this package. Pin with `exact:` if your results must track one tr46 release, or use `from:`.
``TR46/TR46/upstreamVersion`` gives the ported tr46 version in code.

## Convert a domain name

``TR46/TR46/toASCII(_:options:)`` returns the ASCII form, or `nil` exactly where tr46 returns
`null`:

```swift
import TR46

TR46.toASCII("Bücher.example")   // "xn--bcher-kva.example"
TR46.toASCII("xn--zz.com")       // nil: not valid Punycode
TR46.toASCII("")                 // "": tr46 returns "" too
```

``TR46/TR46/toUnicode(_:options:)`` always returns a domain, with every label that decodes
decoded, and reports whether any label failed:

```swift
TR46.toUnicode("xn--mnchen-3ya.de")          // (domain: "münchen.de", hadError: false)
TR46.toUnicode("xn--zz.xn--mnchen-3ya.de")   // (domain: "xn--zz.münchen.de", hadError: true)
```

## Choose the options

``TR46/TR46/Options`` has tr46's options under the same names, and every one defaults to `false`,
as in tr46. Those defaults check very little. Set the ones your protocol needs.

The WHATWG URL Standard's [domain to ASCII](https://url.spec.whatwg.org/#concept-domain-to-ascii),
with `beStrict` false, as browsers and whatwg-url use it, turns on
``TR46/TR46/Options/checkBidi`` and ``TR46/TR46/Options/checkJoiners``:

```swift
let url = TR46.Options(checkBidi: true, checkJoiners: true)

TR46.toASCII("EXAMPLE.münchen.de", options: url)   // "example.xn--mnchen-3ya.de"
TR46.toASCII("\u{0628}\u{200C}a", options: url)    // nil: the ZWNJ fails ContextJ
```

The URL Standard also treats an empty result as a failure, so check for `""` as well as `nil`.
With `beStrict` true, it also sets ``TR46/TR46/Options/useSTD3ASCIIRules`` and
``TR46/TR46/Options/verifyDNSLength``.

| Option | UTS #46 flag |
| --- | --- |
| ``TR46/TR46/Options/checkHyphens`` | `CheckHyphens` |
| ``TR46/TR46/Options/checkBidi`` | `CheckBidi` |
| ``TR46/TR46/Options/checkJoiners`` | `CheckJoiners` |
| ``TR46/TR46/Options/useSTD3ASCIIRules`` | `UseSTD3ASCIIRules` |
| ``TR46/TR46/Options/transitionalProcessing`` | `Transitional_Processing` |
| ``TR46/TR46/Options/verifyDNSLength`` | `VerifyDnsLength` (``TR46/TR46/toASCII(_:options:)`` only) |
| ``TR46/TR46/Options/ignoreInvalidPunycode`` | `IgnoreInvalidPunycode` (changes no result in tr46 7.0.0) |

``TR46/TR46/Options/normalization`` picks the NFC implementation; see <doc:NormalizationModes>.

## Limits of IDNA

UTS #46 makes no judgement about confusable or mixed-script names. `p\u{0430}ypal.com`, with a
Cyrillic `а`, converts to `xn--pypal-4ve.com` without error, even with every check on. For
confusables, see [UTS #39](https://www.unicode.org/reports/tr39/).

Without ``TR46/TR46/Options/verifyDNSLength`` there is no length limit. With
``TR46/TR46/Normalization/bundled`` the work grows linearly, or as O(n log n) for Punycode, but a
caller that accepts arbitrary input should cap its length first. With `.foundation` the cap matters
more, because Foundation's NFC is quadratic in the length of a run of combining marks; see
<doc:NormalizationModes>.
