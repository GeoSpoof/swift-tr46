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

- Nothing guarantees that JavaScriptCore and Foundation use the same Unicode version. On macOS
  13–15, Safari updates ship their own WebKit and JavaScriptCore, separately from the OS.
- NFC is stable for assigned characters under Unicode's normalization stability policy, so two
  correct implementations can differ only on characters that one data version assigns and the
  other doesn't.
- `.bundled` gives the Unicode 18.0.0 answer everywhere. tr46 itself normalizes with whatever
  engine runs it, so for characters newer than that engine's Unicode version, tr46's result
  depends on the engine.
- Foundation's NFC is not always correct. On macOS 27.0.1 it gives the wrong NFC for 4
  NormalizationTest inputs: U+1100 U+AC00 U+11A8, the same with a second U+11A8, U+1100 U+1161
  U+11A7, and U+0CCA U+0CD5. The bundled NFC, ICU and NormalizationTest agree on the right answer.
  So `.foundation` can differ from tr46 running on JavaScriptCore, which uses ICU, for a domain
  holding one of these sequences. None of them occurs in the IdnaTestV2, GeoSpoof or differential
  inputs that the `.foundation` tests run.

## Platforms

`.foundation` exists only where `canImport(Darwin)` is true. On Linux,
`precomposedStringWithCanonicalMapping` comes from swift-corelibs-foundation with its own tables,
so there is no JavaScript engine on the same device for it to match, and supporting it would make
the library import Foundation on Linux, which pulls ICU data into static server binaries. On Linux
the library needs only the standard library, and ``TR46/TR46/Normalization/bundled`` is the only
case.
