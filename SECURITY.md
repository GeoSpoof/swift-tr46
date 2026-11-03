# Security policy

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub's
private vulnerability reporting:

1. Go to the [Security tab](https://github.com/GeoSpoof/swift-tr46/security) of this repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the version, and an input that shows it.

The report is visible only to the maintainers. We aim to reply within a few days. If a fix is
needed, we will publish it with an advisory and credit you, unless you would rather not be named.

## In scope

- A crash or trap on any input, with any options. `toASCII` and `toUnicode` are meant to return a
  result for every `String`.
- Time or memory that grows faster than O(n log n) in the input length.
- A result that differs from tr46 7.0.0's in a way someone could exploit, for example two
  components that are meant to agree on a hostname reaching different answers. A difference from
  tr46 that isn't listed under "Differences from tr46" in the README is a bug in any case; report
  it as an issue if it has no security impact.
- The generators and the CI workflows in this repository, for example a way to get unverified
  upstream data into the generated tables.

## Not in scope

- Confusable or mixed-script names, such as a Cyrillic letter in place of a Latin one. UTS #46
  doesn't address them and this package makes no judgement about them; that is
  [UTS #39](https://www.unicode.org/reports/tr39/)'s subject.
- Behaviour that tr46 7.0.0 has too, such as `ignoreInvalidPunycode` changing nothing. The package
  reproduces tr46 on purpose. Report those to [tr46](https://github.com/jsdom/tr46) or to
  [Unicode](https://www.unicode.org/reporting.html), as appropriate.
- Long inputs being slow when the caller doesn't bound them, as long as the growth is within
  O(n log n). See the README's security notes.

## Supported versions

Only the latest release receives security fixes.
