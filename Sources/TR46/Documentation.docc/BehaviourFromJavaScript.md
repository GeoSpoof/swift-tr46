# Behaviour from JavaScript

The JavaScript string behaviours and tr46 control-flow details the port reproduces, and the one it
doesn't.

## Overview

tr46 runs on JavaScript strings, which are sequences of UTF-16 code units, and some of its results
follow from that. Others follow from the exact order of its steps. Each item below is a curated
input in the differential tests and has a named test.

## JavaScript strings

- term J1. Decoded values re-pair: Punycode can decode to surrogate values, which
  `String.fromCodePoint` accepts, and the JavaScript string then reads a high-low pair as one code
  point. `xn--8c9bk9h.com` gives `xn--e28h.com`, and `xn--a-8f4gp1m.com` gives `xn--a-jv3s.com`.
  `xn--8c9b.com` and `xn--8c9bj9h.com`, whose surrogates don't pair, give `nil`.

- term J2. A decoded value above U+10FFFF fails: `String.fromCodePoint` throws a `RangeError`, so
  decoding fails. `xn--en32g.com` gives `nil`.

- term J3. A lone surrogate in toUnicode's output becomes U+FFFD: tr46 gives
  `{domain: "\uD83D.com", error: true}` for `toUnicode("xn--8c9b.com")`. A Swift `String` can't
  hold a lone surrogate, so ``TR46/TR46/toUnicode(_:options:)`` returns `("\u{FFFD}.com", true)`,
  as `String.prototype.toWellFormed()` would. It only happens with an error: a lone surrogate can
  appear only in a decoded label, and that label is either not validated, because an error was
  already found, or validated and refused, because U+D800–U+DFFF are disallowed.

- term J4. Inputs with lone surrogates can't be represented: they can't be passed in, so 2
  IdnaTestV2 lines and 2 web-platform-tests inputs are skipped.

- term J5. CheckHyphens counts code points: positions 3 and 4 are counted as `Array.from` does,
  not in UTF-16 units. With ``TR46/TR46/Options/checkHyphens``, `"😀b--c"` gives `nil` and
  `"ab😀--c"` gives `"xn--ab--c-0224d"`. Without it, `"😀b--c"` gives `"xn--b--c-u973c"`.

- term J6. verifyDNSLength counts UTF-16 units: tr46 uses `.length`. That is only observable on
  the ASCII result, where units and bytes are the same.

- term J7. Punycode decoding reads UTF-16 units: punycode.js uses `lastIndexOf` and `charCodeAt`.
  That can't change a result: any non-ASCII unit fails decoding wherever it is, so the port reads
  code points.

- term J8. The NFC check compares code units exactly: tr46 refuses a label when
  `label.normalize("NFC") !== label`. The port compares code point arrays, never with Swift's
  `String ==`, which is canonical equivalence.

- term J9. Splitting keeps empty labels: `split(".")` keeps them, so `a..b.com`, `example.com.`,
  `"."` and `""` all keep their empty labels. Without other checks they come back unchanged.

- term J10. Character classes see a lone surrogate's raw value: tr46's `/u` regexes test a lone
  surrogate by its value, and the generated tables are built the same way.

- term J11. IdnaTestV2's escapes: the data lines use only `\uXXXX`, the form tr46's harness reads.
  The generator handles `\x{…}` too, and asserts that the data lines don't use it.

- term J12. Not reproduced, the decoding length limit: tr46 builds a decoded label with
  `String.fromCodePoint(...output)`, which throws "Maximum call stack size exceeded" somewhere
  between 120,000 and 125,000 code points on Node 24.12.0, depending on the engine and the stack.
  The port decodes any length. This is the one deliberate difference in results, and the
  differential inputs stay well below the limit.

## tr46 control flow

- term T1. The error is sticky, and later labels are still decoded:
  `toUnicode("xn--zz.xn--mnchen-3ya.de")` gives `("xn--zz.münchen.de", true)`.

- term T2. An `xn--` label holding non-ASCII: it is an error, and the label is kept as typed rather
  than decoded. `toUnicode("xn--ü.com")` gives `("xn--ü.com", true)`.

- term T3. ignoreInvalidPunycode changes nothing in 7.0.0: a label that fails to decode stays as
  its ASCII `xn--` form, and the next check, that a decoded label is non-empty and holds a
  non-ASCII code point, sets the error anyway. ``TR46/TR46/Options/ignoreInvalidPunycode`` is
  ported as written, and a test checks that both values give the same result on every vector.

- term T4. A decoded label that is empty or all ASCII is an error: `xn--.com`, `xn--a.com` and
  `xn--zz.com` all give `nil` from ``TR46/TR46/toASCII(_:options:)``.

- term T5. Transitional processing never applies to decoded labels: they are always validated
  nontransitionally. `toUnicode("xn--zca.de")` with transitional processing gives
  `("ß.de", false)`.

- term T6. U+1E9E maps to "ss" under transitional processing: `toASCII("ẞ.de")` gives `"ss.de"`
  with ``TR46/TR46/Options/transitionalProcessing`` and `"xn--zca.de"` without it. The deviation
  characters map only under transitional processing: ß to `ss`, ς to `σ`, and ZWNJ and ZWJ to
  nothing.

- term T7. The ContextJ check accepts a ZWNJ after an earlier allowed one:
  `"\u{0628}\u{094D}\u{200C}\u{0628}\u{200C}a"` with ``TR46/TR46/Options/checkJoiners`` gives
  `"xn--a-0mca333a472bba"`. The second ZWNJ passes because the text before it still holds the first
  one, which the virama let through. `"\u{0628}\u{200C}a"` gives `nil`.

- term T8. Punycode overflow fails only toASCII: `"a"` × 10,950 followed by U+30000 overflows the
  encoder, so ``TR46/TR46/toASCII(_:options:)`` gives `nil`, while
  ``TR46/TR46/toUnicode(_:options:)`` reports no error. With 10,900 `a`s it encodes.

- term T9. DNS lengths: with ``TR46/TR46/Options/verifyDNSLength``, a 63-character label passes and
  a 64-character one fails, a total above 253 fails, and so do `""` and `example.com.`, whose last
  label is empty.

- term T10. The encoder's per-round multiplier: punycode.js computes `handledCPCountPlusOne` once
  per round. That can't change any output, but both of the port's encoders keep it as written.

- term T11. The bidi decision is made once, from all labels: tr46 decides whether a domain is a
  bidi domain before any label is replaced by its decoded form, and a label that fails to decode
  contributes nothing.

- term T12. An empty label under CheckBidi is not a toUnicode error: IdnaTestV2 marks it with the
  status X4_2. tr46 doesn't treat it as an error, and the conformance tests read it the same way.
  `toUnicode("\u{05D0}..b")` with ``TR46/TR46/Options/checkBidi`` gives `("א..b", false)`.

## Punycode performance

punycode.js inserts each decoded code point into an array and scans the input once per distinct
value, which is O(n²). Up to 1,024 code points the port runs that algorithm line for line. Above
that it runs the same loop, the same arithmetic and the same overflow checks in the same order,
and places code points with a Fenwick tree, in O(n log n). Both paths are tested on the same
inputs and agree.
