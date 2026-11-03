# Normalization modes

Choose which NFC implementation the two normalization steps use.

## Overview

UTS #46 normalizes to NFC twice: the whole mapped domain, and a check that each label is already in
NFC. tr46 calls JavaScript's `String.prototype.normalize("NFC")` for both. Both steps here go
through the mode in ``TR46/TR46/Options/normalization``.

- term ``TR46/TR46/Normalization/bundled``: Unicode 18.0.0 NFC tables compiled into the package.
  The answer is the same on every OS and platform. This is the default.
- term `.foundation`: Foundation's `precomposedStringWithCanonicalMapping`, which uses the OS's
  normalization data. Only on Apple platforms.

``TR46/TR46/Normalization`` is a structure with these as static properties, not an enumeration,
so later releases may add modes without breaking your code. A `switch` over it needs a `default:`
case.

## Why the package carries its own NFC

Swift has no public normalization API. In the Swift 6.4 standard library's interface the only
normalization symbols are underscored (`String._nfcCodeUnits`, `String._withNFCCodeUnits`), and
the 2024 [Unicode Normalization pitch](https://forums.swift.org/t/pitch-unicode-normalization/73240)
did not become API. On Apple platforms the standard library ships with the OS, so its Unicode data
would change with the OS version anyway.

The bundled NFC passes all 20,171 lines of Unicode's NormalizationTest 18.0.0, and leaves every
other code point, 1,094,910 of them, unchanged.

## When to use the Foundation mode

`.foundation` is for apps that have to agree with tr46 running in a browser on the same device.
GeoSpoof uses it because its Safari extension runs tr46, and tr46 calls JavaScriptCore's
`normalize("NFC")` on the same device.

How far apart the modes can be:

- `.foundation` is not the normalizer Safari's tr46 uses. JavaScriptCore's `normalize("NFC")`
  calls ICU (`unorm2_getNFCInstance`, in WebKit's `StringPrototype.cpp`), and on macOS 27.0.1
  JavaScriptCore links the OS's ICU, `/usr/lib/libicucore.A.dylib`. WebKit on Apple platforms
  builds against the OS's ICU rather than bundling one, so although Safari updates on macOS 13–15
  ship their own WebKit and JavaScriptCore, separately from the OS, they don't bring other NFC
  data. Foundation's `precomposedStringWithCanonicalMapping` is a separate implementation with its
  own data. So `.foundation` is a second normalizer on the same OS, and nothing guarantees that it
  and ICU use the same Unicode version.
- NFC is stable for assigned characters under Unicode's normalization stability policy, so two
  correct implementations can differ only on characters that one data version assigns and the
  other doesn't.
- `.bundled` gives the Unicode 18.0.0 answer everywhere. tr46 itself normalizes with whatever
  engine runs it, so for characters newer than that engine's Unicode version, tr46's result
  depends on the engine.
- Foundation's NFC is not always correct. On macOS 27.0.1 it gives the wrong NFC for 4
  NormalizationTest inputs: U+1100 U+AC00 U+11A8, the same with a second U+11A8, U+1100 U+1161
  U+11A7, and U+0CCA U+0CD5. The bundled NFC, NormalizationTest, and JavaScriptCore's
  `normalize("NFC")` on the same OS agree on the right answer. So `.foundation` can differ from
  tr46 running on JavaScriptCore for a domain holding one of these sequences. None of them occurs
  in the IdnaTestV2, GeoSpoof or differential inputs that the `.foundation` tests run.

## Performance of the Foundation mode

Foundation's NFC takes time quadratic in the length of a run of combining marks, and
`.foundation` calls it twice per input: once for the whole domain and once for each non-ASCII
label. In a release build on macOS 27.0.1 (Apple M4), ``TR46/TR46/toASCII(_:options:)`` of `a`
followed by alternating U+0316 and U+0301 took:

| Marks | `.foundation` | ``TR46/TR46/Normalization/bundled`` |
| ---: | ---: | ---: |
| 5,000 | 0.030 s | 0.002 s |
| 10,000 | 0.116 s | 0.003 s |
| 20,000 | 0.476 s | 0.006 s |
| 40,000 | 1.762 s | 0.013 s |

Each doubling takes about four times as long with `.foundation`, and about twice as long with
``TR46/TR46/Normalization/bundled``. This package can't change Foundation's algorithm without
changing what the mode means. If you use `.foundation` on untrusted input, bound its length first.

JavaScriptCore's `normalize("NFC")`, measured on the same input and OS, grows at the same rate
(2.24 s at 40,000 marks), so tr46 running in Safari has this cost too.

## Platforms

`.foundation` exists only where `canImport(Darwin)` is true. On Linux,
`precomposedStringWithCanonicalMapping` comes from swift-corelibs-foundation with its own tables,
so there is no JavaScript engine on the same device for it to match, and supporting it would make
the library import Foundation on Linux, which pulls ICU data into static server binaries. On Linux
the library needs only the standard library, and ``TR46/TR46/Normalization/bundled`` is the only
mode.
