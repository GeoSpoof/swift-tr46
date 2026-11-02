# swift-tr46

A Swift port of [tr46](https://github.com/jsdom/tr46), jsdom's implementation of
[Unicode IDNA Compatibility Processing (UTS #46)](https://www.unicode.org/reports/tr46/),
together with the Punycode encoder and decoder from
[punycode.js](https://github.com/mathiasbynens/punycode.js).

It converts domain names between their Unicode and ASCII (`xn--`) forms with
`toASCII` and `toUnicode`. The goal is the same result as tr46 for every input
and every option.

## Status

In development, with no release yet. The first release will be 7.0.0, porting
tr46 7.0.0 (Unicode 18.0.0) and punycode.js 2.3.1.

## Versioning

The major and minor version match the tr46 release being ported. The patch
number belongs to this package: a fix to the port and a tr46 patch release both
ship as the next patch, so a version number never refers to two different sets
of code. The ported tr46 version is listed here and will also be available in
code as `TR46.upstreamVersion`.

## License

MIT, see [LICENSE](LICENSE). The generated Unicode data is covered by the
Unicode License V3, see [NOTICE](NOTICE).
