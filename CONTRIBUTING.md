# Contributing

swift-tr46 is a port: its job is to give tr46 7.0.0's answer for every input. A change that makes
any result differ from tr46's is a bug, however reasonable the new result looks, unless it is one
of the differences listed in the README. If you think tr46 is wrong, report it to
[tr46](https://github.com/jsdom/tr46) first; this package follows it when it changes.

## Toolchains

- **Swift 6.0 or later**: Xcode 16.0 or later on macOS, or a Swift 6.0+ toolchain on Linux.
- **Node, exactly the version in `.node-version`** (24.12.0), only for regenerating the tables and
  test data. The generators check `process.version`, and Node's Unicode (16.0) and ICU (77.1)
  versions, and refuse to run on anything else, because those versions fix the output byte for
  byte. An official build from nodejs.org, nvm or `actions/setup-node` has the right ICU. npm comes
  with it and is used only for `npm pack`.

## Building and testing

```sh
swift build -Xswiftc -warnings-as-errors
swift test
```

The full suite takes about 50 seconds in debug on a 10-core Mac. `DifferentialTests` is most of
it, about 45 seconds; it is CPU-bound and split into 32 shards, so it takes longer on fewer cores.
Run one or more suites with `--filter`:

```sh
swift test --filter APITests
swift test --filter "IdnaTestV2Tests|WPTTests"
swift test --skip-build --no-parallel --filter PerformanceTests   # for meaningful durations
```

The suites are `TablesTests`, `NormalizationTests`, `PunycodeTests`, `APITests`,
`IdnaTestV2Tests`, `WPTTests`, `GeoSpoofFixtureTests`, `FastPathTests`, `DifferentialTests` and
`PerformanceTests`. Each conformance suite prints one `[conformance]` or `[differential]` summary
line.

On Linux, or from macOS with Docker, using the same images as CI:

```sh
for image in swift:6.0.3-noble swift:6.4.2-noble; do
  docker run --rm -v "$PWD":/src:ro "$image" bash -c 'mkdir /tmp/src &&
    tar -C /src --exclude=./.build --exclude=./Benchmarks/.build -cf - . | tar -C /tmp/src -xf - &&
    cd /tmp/src && swift test'
done
```

The tree is copied inside the container rather than built from the mount. Files on macOS can
carry extended attributes such as `com.apple.provenance`, which a Linux filesystem refuses, and
SwiftPM's copy of the test resources from the mount then fails with `NSCocoaErrorDomain` error
512. `tar` leaves the attributes behind.

Apple platforms other than macOS, and the documentation:

```sh
xcodebuild -scheme swift-tr46 -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/tr46-dd build
xcodebuild docbuild -scheme swift-tr46 -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/tr46-docc OTHER_DOCC_FLAGS=--warnings-as-errors
```

The Xcode scheme is `swift-tr46`, the package name, not `TR46`. Pass a `-derivedDataPath` outside
the repository so nothing lands in the working tree.

The benchmark is a separate package, so the library's manifest never exposes an executable:

```sh
swift run -c release --package-path Benchmarks TR46Benchmark
```

It has no thresholds. CI builds it but doesn't run it.

## Generated files

Never edit these by hand:

- `Sources/TR46/Generated/IDNATables.swift`, from tr46 7.0.0's `lib/mappingTable.json`,
  `lib/regexes.js` and `lib/statusMapping.js`
- `Sources/TR46/Generated/NFCTables.swift`, from the Unicode 18.0.0 UCD
- `Tests/TR46Tests/Resources/{normalization-test,idna-test-v2,wpt-toascii,differential}.json`

Two files in `Tests/TR46Tests/Resources/` are copied, not generated, and the generator checks both
by hash: `geospoof-idna-vectors.json` (from the GeoSpoof repository) and
`LICENSE-web-platform-tests.md` (WPT's `LICENSE.md` at the pinned commit).

```sh
Scripts/regenerate.sh           # regenerate everything (about 15 s)
Scripts/regenerate.sh --check   # regenerate, then fail if anything differs from what is committed
```

The CI job **Generated files** runs `--check`. Every upstream input is pinned in
`Scripts/lib/sources.mjs` and verified by hash each time it is read, whether it was just
downloaded, read from the cache in `.build/tr46-sources/`, or passed with `--tr46-tarball`,
`--punycode-tarball`, `--unicode-dir` or `--data-dir`. A cached file that fails its hash is an
error; delete it to fetch it again. Raw upstream files are never committed.

Every assumption the Swift code makes about the data is an assertion in a generator, and a failed
assertion exits 1 before anything is written.

`Scripts/generate-tables.mjs` asserts, among other things:

- the tarballs' sha512 and the SHA-256 of every member used, the Unicode files' sizes and hashes,
  and that tr46's `unicodeVersion` is the pinned one
- `statusMapping.js`'s values, and that `mappingTable.json` covers U+0000–U+10FFFF contiguously
- that D800–DFFF are disallowed (the port's lone-surrogate rule relies on it), U+002E is valid, the
  deviation rows are exactly the expected set, and U+1E9E maps to U+00DF
- that A–Z map to lower case and every other ASCII code point is valid, which the ASCII fast path
  relies on, and that the combining-mark, virama, ZWNJ-context and bidi-domain classes hold no
  ASCII and the ZWNJ-context classes hold neither joiner
- that each `regexes.js` regex has the expected shape and flags, and that each extracted class
  agrees with the live regex at every code point, surrogates included
- that the packed IDNA table gives back `mappingTable.json` at every code point, and every packed
  field fits its bit width
- for NFC: the Hangul range, decomposition lengths, that no pair composes to two different characters,
  that NFC_QC=No and Maybe don't overlap, and that ASCII is inert under NFC
- that a JavaScript NFC built only from the packed arrays passes every NormalizationTest 18.0.0
  invariant and agrees with Node's NFC on every test string Node's Unicode version can represent

`Scripts/generate-vectors.mjs` asserts:

- the expected line and part counts of NormalizationTest.txt and IdnaTestV2.txt, and that
  IdnaTestV2's data lines use only `\uXXXX` escapes
- that real tr46 7.0.0, loaded from the verified tarball, gives every expected IdnaTestV2 answer
  under the strict reading, every selected WPT answer, and every answer in the GeoSpoof fixture
- the fixture's SHA-256 and counts, and the WPT licence copy's hash
- that lone surrogates appear only in the 2 IdnaTestV2 and 2 WPT inputs that are skipped, and in
  `toUnicode` answers only together with an error
- for `differential.json`: that each input's answers cover every option combination exactly once,
  that some code point really is newer than Node (so the exclusion rule is live), exactly 3,000
  fuzz inputs, and that the per-source counts add up

## Updating to a new tr46 or Unicode version

1. **Pins.** In `Scripts/lib/sources.mjs`:
   - `TR46`: the version, `npm view tr46@X.Y.Z dist.integrity`, `unicodeVersion`, and the SHA-256
     of each member. Get them from the tarball `npm pack tr46@X.Y.Z` writes.
   - `UNICODE`: the version, the base URL, and each file's size and SHA-256.
   - `WPT`: the commit is the `wptSHA` in tr46's `scripts/getLatestTests.mjs` at the new tag; then
     each file's size and SHA-256 at that commit, including `LICENSE.md`.
   - `PUNYCODE`, if tr46's `package.json` now depends on a different punycode.
2. **Port.** Diff tr46's `index.js` between the two tags, and punycode.js if it changed, and port
   each change into the matching Swift function, keeping tr46's step order and step comments.
   Update the SHA-256 in the header of each ported file. Check whether `regexes.js` gained or lost a
   regex, which `Scripts/lib/tr46-data.mjs` will report.
3. **Versions.** Update `TR46.upstreamVersion` and `TR46.unicodeVersion` in
   `Sources/TR46/TR46.swift`.
4. **Expected counts.** Update the counts the generators assert (NormalizationTest parts,
   IdnaTestV2 lines, the WPT selections) and any the tests assert. Each failed assertion names
   the file and the number it found.
5. **The GeoSpoof fixture** records tr46 7.0.0's answers, and the generator checks that it was
   produced by the pinned tr46. Copy a fixture regenerated with the new tr46 from the GeoSpoof
   repository and update `SEED_FIXTURE`, or record why the old one still applies.
6. **Regenerate and test.** `Scripts/regenerate.sh`, then `swift test`. Every `[conformance]` and
   `[differential]` line must be at 100%.
7. **Docs.** Update the counts in the README and `Conformance.md`, add a CHANGELOG section, and
   follow the versioning rule in the README: a new tr46 minor or major is a new minor or major
   here; a tr46 patch is the next patch.

## Bumping Node, the Swift images and Xcode

Dependabot only updates the GitHub Actions. These are bumped by hand:

- **Node.** Change `.node-version` and `NODE` in `Scripts/lib/sources.mjs` together. A Node with a
  different Unicode or ICU version changes which inputs count as newer than Node, so
  `differential.json` will change; regenerate and review the diff.
- **Swift images.** `ci.yml` pins `swift:6.0.3-noble` and the latest release by digest. Get the
  digest with
  `curl -fsSL https://hub.docker.com/v2/repositories/library/swift/tags/<tag> | jq -r .digest`,
  and update the `docker run` lines above. Keep the 6.0 entry: it is the oldest supported Swift.
- **Xcode.** The **macOS (latest Xcode)** job picks the newest released Xcode on the image, and
  **macOS (Xcode 16)** the oldest Xcode 16, so they follow runner image updates. **Analyze (Swift)**
  in `codeql.yml` pins an Xcode on purpose, because CodeQL analyzes only the Swift versions its
  bundle supports. Before moving it, check the
  [supported compilers](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
  for the bundle the codeql-action pin uses (the action's `src/defaults.json` names it).
- **Runner images.** `macos-26`, `macos-15` and `ubuntu-24.04` are named explicitly.

## Pull requests

- `main` takes changes only through pull requests, which are squash-merged.
- Every commit that reaches `main` must be signed (the ruleset requires signatures), so sign your
  commits.
- The required checks are: **macOS (latest Xcode)**, **macOS (Xcode 16)**, **Linux (Swift 6.0)**,
  **Linux (latest Swift)**, **Generated files**, **gitleaks**, **zizmor**, **Dependency review** and
  **Analyze (Swift)**. Their names are part of the ruleset, so renaming a job, or giving a required
  workflow a path filter, blocks every pull request until the ruleset is updated.
- Workflow changes must pass zizmor at medium severity and actionlint. Pin every action to a full
  commit SHA with a version comment, keep `permissions: {}` at the top of each workflow, and pass
  values to `run:` through `env:`.
- Use [Conventional Commits](https://www.conventionalcommits.org/) subjects: `feat:`, `fix:`,
  `test:`, `ci:`, `docs:`, `chore:`.

## Documentation style

Plain, direct and specific. Say what the code does and give the real number, with where it came
from. No marketing words and no emoji. When a statement depends on an outside project or a date,
such as a runner image's Xcode or another library's status, say when it was checked.

Public symbols carry `///` documentation that names the tr46 behaviour and, for an option, its UTS
#46 flag. The DocC catalog is in `Sources/TR46/Documentation.docc/`, and `docbuild` must report no
warnings.
