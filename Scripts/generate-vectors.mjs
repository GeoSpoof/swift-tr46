/**
 * generate-vectors.mjs
 *
 * Writes the test data in Tests/TR46Tests/Resources, one section per file:
 *   normalizationVectors()   normalization-test.json   Unicode 18.0.0's NormalizationTest.txt
 *   idnaTestV2Vectors()      idna-test-v2.json         Unicode 18.0.0's IdnaTestV2.txt, resolved strictly
 *   wptVectors()             wpt-toascii.json          WPT toascii.json and IdnaTestV2.json at tr46's pin
 *   checkSeedFixture()       (writes nothing)          geospoof-idna-vectors.json, copied verbatim, is checked
 *   differentialVectors()    differential.json         real tr46's answers under all 128 + 64 option combinations
 *
 * Every expected IDNA answer is checked against real tr46 7.0.0 from the verified tarball, and the
 * run fails on the first one tr46 doesn't give. differential.json's answers are tr46's own.
 *
 *   Scripts/regenerate.sh           # both generators (preferred)
 *   node Scripts/generate-vectors.mjs [--unicode-dir d] [--data-dir d] [--tr46-tarball p] [--punycode-tarball p]
 *
 * Raw upstream files are never committed. Each one is read through Scripts/lib/sources.mjs,
 * verified by hash, and re-encoded as deterministic JSON: one vector per line, with every UTF-16
 * unit above U+007E written as a \uXXXX escape, so no tool can renormalize the data. Every count
 * a file promises is asserted here.
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { NODE, PUNYCODE, ROOT, SEED_FIXTURE, Sources, TR46, UNICODE, WPT, fail, parseArgs, run, sha256 } from "./lib/sources.mjs";
import {
  ageLookup,
  ageRank,
  parseDerivedAge,
  parseIdnaStatus,
  parseIdnaTestV2,
  parseNormalizationTest,
  parseUnicodeData,
} from "./lib/ucd.mjs";
import { mapChars, readClasses, readMappingTable, readStatusMapping } from "./lib/tr46-data.mjs";
import { FUZZ_COUNT, FUZZ_SEED, createFuzzer, createPools, createRandom } from "./lib/fuzz.mjs";
import { vectorFile, writeOutput } from "./lib/emit.mjs";

const TAG = "generate-vectors";
const RESOURCES = "Tests/TR46Tests/Resources";
const GENERATOR = "Scripts/regenerate.sh";

/** A JS string with a lone surrogate (a paired one is a single code point under /u). */
const LONE_SURROGATE = /\p{Cs}/u;

/** tr46's harnesses skip these: the URL Standard bypasses IDNA processing for ASCII domains. */
const ALL_ASCII = /^[\x00-\x7F]*$/u;

/** A string's code points, in for…of order. */
const codePointsOf = (text) => [...text].map((ch) => ch.codePointAt(0));

/** Shows a string with everything outside printable ASCII escaped, for failure messages. */
const show = (value) => (value === null ? "null" : JSON.stringify(value).replace(/[^\x20-\x7e]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`));

/**
 * The Unicode version every supported OS and CI image ships. NFC is identical across versions
 * for assigned characters, so a vector whose code points are all this old is safe to check
 * against Foundation's NFC; a newer one carries an `age` and the .foundation tests skip it.
 */
const AGE_FLOOR = "14.0";

/** The highest DerivedAge among the assigned code points, if it is above AGE_FLOOR. */
function ageAboveFloor(ageOf, codePoints) {
  let highest = null;
  for (const cp of codePoints) {
    const age = ageOf(cp);
    if (age !== null && (highest === null || ageRank(age) > ageRank(highest))) highest = age;
  }
  return highest !== null && ageRank(highest) > ageRank(AGE_FLOOR) ? highest : null;
}

// ── normalization-test.json ────────────────────────────────────────────────────

async function normalizationVectors(sources) {
  const test = await sources.unicode("NormalizationTest");
  const age = await sources.unicode("DerivedAge");
  if (!age.text.startsWith(`# DerivedAge-${UNICODE.version}.txt\n`)) fail(`${age.path} is not version ${UNICODE.version}`);
  const ageOf = ageLookup(parseDerivedAge(age.text));
  const { parts, lines } = parseNormalizationTest(test.text);

  const expected = { part0: 46, part1: 17154, part2: 2004, part3: 194, part4: 735, part5: 38 };
  const counts = Object.fromEntries(parts.map((_, part) => [`part${part}`, lines.filter((l) => l.part === part).length]));
  if (JSON.stringify(counts) !== JSON.stringify(expected)) {
    fail(`NormalizationTest has ${JSON.stringify(counts)}, expected ${JSON.stringify(expected)}`);
  }

  let withAge = 0;
  const vectors = lines.map((l) => {
    const newest = ageAboveFloor(ageOf, l.columns.flat());
    if (newest === null) return [l.part, ...l.hex];
    withAge++;
    return [l.part, ...l.hex, newest];
  });

  const header = {
    about:
      `Unicode ${UNICODE.version}'s NormalizationTest.txt, re-encoded as one vector per line: ` +
      "[part, c1, c2, c3, c4, c5, age?], each column in the file's own hex form. " +
      "NormalizationTests checks every NFC invariant over them: c2 == NFC(c1) == NFC(c2) == NFC(c3) and " +
      "c4 == NFC(c4) == NFC(c5), and NFC(X) == X for every code point outside Part 1. " +
      `age is the highest DerivedAge among a vector's code points, present only above ${AGE_FLOOR}; ` +
      "the .foundation comparison skips those vectors.",
    license:
      `Derived from Unicode's NormalizationTest.txt and DerivedAge.txt ${UNICODE.version}, ` +
      "Copyright \u00a9 1991-2026 Unicode, Inc., under the Unicode License V3 (https://www.unicode.org/license.txt). See NOTICE.",
    source: {
      version: UNICODE.version,
      files: {
        [test.path]: { url: test.url, sha256: test.sha256 },
        [age.path]: { url: age.url, sha256: age.sha256 },
      },
    },
    generator: GENERATOR,
    counts,
  };
  const output = vectorFile(header, { vectors });
  return {
    file: `${RESOURCES}/normalization-test.json`,
    output,
    summary: `${vectors.length} vectors (${withAge} with an age above ${AGE_FLOOR})`,
  };
}

// ── tr46 itself ────────────────────────────────────────────────────────────────

/**
 * Real tr46 7.0.0 from the verified tarball, which every expected answer below is checked against,
 * and mapChars over its own table for age tagging.
 */
function loadTr46(sources) {
  const { tr46: pkg } = sources.packages();
  const tr46 = pkg.load();
  const status = readStatusMapping(pkg);
  const rows = readMappingTable(pkg, status);
  return {
    tr46,
    // The punycode.js 2.3.1 module tr46 itself loads (sources.mjs checks the resolution).
    punycode: pkg.require("punycode/"),
    pkg,
    rows,
    status,
    mapChars: (text, transitionalProcessing) => mapChars(rows, status, text, transitionalProcessing),
  };
}

// ── idna-test-v2.json ──────────────────────────────────────────────────────────

/** tr46's test/unicode.js at v7.0.0. */
const IDNA_TEST_OPTIONS = {
  toUnicode: { checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true },
  toASCII: { checkHyphens: true, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: true, verifyDNSLength: true },
};

/**
 * IdnaTestV2.txt, each row resolved strictly by the file's own rules, and every
 * answer checked against real tr46. Stricter than tr46's harness in three ways: a blank status
 * inherits as the file documents (the harness reads it as no error), toASCII must give exactly the
 * expected value (the harness accepts a null), and toUnicode's domain and error are compared on
 * every row. Real tr46 7.0.0 passes all 6,396 rows this way, the lone-surrogate ones included.
 */
async function idnaTestV2Vectors(sources, { tr46, mapChars: map }, ageOf) {
  const file = await sources.unicode("IdnaTestV2");
  if (!new RegExp(`^# Version: ${UNICODE.version.replace(/\./g, "\\.")}$`, "m").test(file.text)) {
    fail(`${file.path} has no "# Version: ${UNICODE.version}" line`);
  }
  const rows = parseIdnaTestV2(file.text);
  const expectedCounts = { lines: 6396, skippedLoneSurrogate: 2, vectors: 6394 };
  if (rows.length !== expectedCounts.lines) fail(`IdnaTestV2.txt has ${rows.length} test lines, expected ${expectedCounts.lines}`);

  const vectors = [];
  let skippedLoneSurrogate = 0;
  let withAge = 0;
  for (const row of rows) {
    const where = `IdnaTestV2.txt:${row.line}`;
    if (row.source === null) fail(`${where}: no source`);
    const source = row.source;
    // "A blank value means the same as the source value."
    const toUnicode = row.toUnicode ?? source;
    // "A blank value means [] (no errors)."
    const toUnicodeStatus = row.toUnicodeStatus === null ? [] : parseIdnaStatus(row.toUnicodeStatus, where);
    // "A blank value means the same as the toUnicode value."
    const toAsciiN = row.toAsciiN ?? toUnicode;
    // "A blank value means the same as the toUnicodeStatus value."
    const toAsciiNStatus = row.toAsciiNStatus === null ? toUnicodeStatus : parseIdnaStatus(row.toAsciiNStatus, where);
    // "A blank value means the same as the toAsciiN value."
    const toAsciiT = row.toAsciiT ?? toAsciiN;
    // "A blank value means the same as the toAsciiNStatus value."
    const toAsciiTStatus = row.toAsciiTStatus === null ? toAsciiNStatus : parseIdnaStatus(row.toAsciiTStatus, where);

    const expected = {
      toUnicode,
      // tr46's harness: "We don't care about X* error codes since they are just bugs in a previous
      // version of the test suite." [X4_2] is an empty label under CheckBidi, which tr46's
      // toUnicode doesn't report (T12).
      toUnicodeError: !(toUnicodeStatus.length === 0 || (toUnicodeStatus.length === 1 && toUnicodeStatus[0] === "X4_2")),
      toASCIIN: toAsciiNStatus.length === 0 ? toAsciiN : null,
      toASCIIT: toAsciiTStatus.length === 0 ? toAsciiT : null,
    };

    const unicode = tr46.toUnicode(source, IDNA_TEST_OPTIONS.toUnicode);
    const asciiN = tr46.toASCII(source, { ...IDNA_TEST_OPTIONS.toASCII, transitionalProcessing: false });
    const asciiT = tr46.toASCII(source, { ...IDNA_TEST_OPTIONS.toASCII, transitionalProcessing: true });
    const mismatches = [];
    if (unicode.domain !== expected.toUnicode) mismatches.push(`toUnicode ${show(unicode.domain)}, expected ${show(expected.toUnicode)}`);
    if (unicode.error !== expected.toUnicodeError) mismatches.push(`toUnicode error ${unicode.error}, expected ${expected.toUnicodeError}`);
    if (asciiN !== expected.toASCIIN) mismatches.push(`toASCII-N ${show(asciiN)}, expected ${show(expected.toASCIIN)}`);
    if (asciiT !== expected.toASCIIT) mismatches.push(`toASCII-T ${show(asciiT)}, expected ${show(expected.toASCIIT)}`);
    if (mismatches.length > 0) fail(`${where} ${show(source)}: tr46 ${TR46.version} gives ${mismatches.join("; ")}`);

    // J4: a Swift String can't hold a lone surrogate, so a source with one is skipped. No
    // expected answer of a kept row may hold one either.
    if (LONE_SURROGATE.test(source)) {
      skippedLoneSurrogate++;
      continue;
    }
    for (const [name, value] of Object.entries(expected)) {
      if (typeof value === "string" && LONE_SURROGATE.test(value)) fail(`${where}: the expected ${name} holds a lone surrogate`);
    }

    const age = ageAboveFloor(ageOf, [
      ...codePointsOf(source),
      ...codePointsOf(map(source, false)),
      ...codePointsOf(map(source, true)),
      ...[expected.toUnicode, expected.toASCIIN, expected.toASCIIT].filter((v) => v !== null).flatMap(codePointsOf),
    ]);
    const vector = { line: row.line, source, ...expected };
    if (age !== null) {
      vector.age = age;
      withAge++;
    }
    vectors.push(vector);
  }

  const counts = { lines: rows.length, skippedLoneSurrogate, vectors: vectors.length };
  if (JSON.stringify(counts) !== JSON.stringify(expectedCounts)) {
    fail(`IdnaTestV2 counts are ${JSON.stringify(counts)}, expected ${JSON.stringify(expectedCounts)}`);
  }

  const header = {
    about:
      `Unicode ${UNICODE.version}'s IdnaTestV2.txt, each row resolved by the file's own rules and re-encoded as one vector ` +
      "per line: {line, source, toUnicode, toUnicodeError, toASCIIN, toASCIIT, age?}. A blank toUnicode is the source, a " +
      "blank toAsciiN is toUnicode and a blank toAsciiT is toAsciiN. A blank toUnicodeStatus is [], a blank toAsciiNStatus " +
      "is toUnicodeStatus and a blank toAsciiTStatus is toAsciiNStatus. toASCIIN and toASCIIT are null unless their " +
      "status is []. toUnicodeError is false only for [] and [X4_2], as in tr46's test/unicode.js. The options are " +
      `tr46's test/unicode.js's. Real tr46 ${TR46.version} gives every one of these answers, which the generator ` +
      `asserts. The ${skippedLoneSurrogate} rows whose source holds a lone surrogate are left out, because a Swift ` +
      `String can't hold one. age is the highest DerivedAge among the assigned code points of the source, its two ` +
      `mapped forms and the expected answers, present only above ${AGE_FLOOR}; the .foundation comparison skips those vectors.`,
    license:
      `Derived from Unicode's IdnaTestV2.txt and DerivedAge.txt ${UNICODE.version}, Copyright \u00a9 1991-2026 Unicode, Inc., ` +
      "under the Unicode License V3 (https://www.unicode.org/license.txt). See NOTICE.",
    source: {
      version: UNICODE.version,
      files: { [file.path]: { url: file.url, sha256: file.sha256 } },
    },
    generator: GENERATOR,
    oracle: { tr46: { version: TR46.version, integrity: TR46.integrity } },
    counts,
    options: IDNA_TEST_OPTIONS,
  };
  return {
    file: `${RESOURCES}/idna-test-v2.json`,
    output: vectorFile(header, { vectors }),
    summary: `${vectors.length} vectors of ${rows.length} lines (${skippedLoneSurrogate} lone-surrogate skipped, ${withAge} with an age above ${AGE_FLOOR})`,
  };
}

// ── wpt-toascii.json ───────────────────────────────────────────────────────────

/** tr46's test/toascii.js at v7.0.0. */
const WPT_OPTIONS = { checkBidi: true, checkHyphens: false, checkJoiners: true, useSTD3ASCIIRules: false, verifyDNSLength: false };

const WPT_LICENSE_COPY = `${RESOURCES}/LICENSE-web-platform-tests.md`;

/**
 * WPT's url/resources/toascii.json and IdnaTestV2.json at the commit tr46 v7.0.0 pins, selected
 * by tr46's test/toascii.js: comment strings are skipped, so are `urlStandardOnly` cases
 * (toascii.json), inputs holding "?" (IdnaTestV2.json) and all-ASCII inputs. Then lone-surrogate
 * inputs are skipped too (J4). Real tr46 matches every case, and the generator asserts it.
 */
async function wptVectors(sources, { tr46 }) {
  const files = { toascii: await sources.wpt("toascii"), idnaTestV2: await sources.wpt("idnaTestV2") };
  const license = await sources.wpt("license");

  // LICENSE-web-platform-tests.md is copied from WPT's LICENSE.md verbatim and committed.
  const copy = readFileSync(path.join(ROOT, WPT_LICENSE_COPY));
  if (sha256(copy) !== WPT.files.license.sha256 || !copy.equals(license.bytes)) {
    fail(`${WPT_LICENSE_COPY} is not WPT's ${license.path} at ${WPT.commit}; copy it again from ${license.url}`);
  }

  const expectedCounts = { toascii: 61, idnaTestV2: 1680 };
  const expectedLone = { toascii: 0, idnaTestV2: 2 };
  const selected = {};
  const skipped = {};
  for (const [key, file] of Object.entries(files)) {
    const entries = JSON.parse(file.text);
    if (!Array.isArray(entries)) fail(`${file.path} is not an array`);
    const skip = { comments: 0, urlStandardOnly: 0, questionMark: 0, ascii: 0, loneSurrogate: 0 };
    const kept = [];
    for (const [index, entry] of entries.entries()) {
      const where = `${file.path}[${index}]`;
      if (typeof entry === "string") {
        // It's a "comment"; skip it.
        skip.comments++;
        continue;
      }
      const keys = Object.keys(entry);
      if (keys.some((k) => !["comment", "input", "output", "urlStandardOnly"].includes(k))) fail(`${where}: keys ${keys.join(", ")}`);
      if (typeof entry.input !== "string" || !(entry.output === null || typeof entry.output === "string")) fail(`${where}: ${show(JSON.stringify(entry))}`);
      if (key === "toascii" && entry.urlStandardOnly) {
        // This test isn't valid for just TR46 ToASCII; it relies on behavior from the URL Standard's "domain to ASCII".
        skip.urlStandardOnly++;
        continue;
      }
      if (key === "idnaTestV2" && entry.urlStandardOnly !== undefined) fail(`${where}: urlStandardOnly, which tr46's harness doesn't skip here`);
      if (key === "idnaTestV2" && entry.input.includes("?")) {
        // ToASCII will not fail on these. But, the URL Standard will.
        skip.questionMark++;
        continue;
      }
      // The URL Standard bypasses IDNA processing for ASCII domains.
      if (ALL_ASCII.test(entry.input)) {
        skip.ascii++;
        continue;
      }
      const actual = tr46.toASCII(entry.input, WPT_OPTIONS);
      if (actual !== entry.output) fail(`${where} ${show(entry.input)}: tr46 ${TR46.version} gives ${show(actual)}, expected ${show(entry.output)}`);
      if (LONE_SURROGATE.test(entry.input)) {
        skip.loneSurrogate++;
        continue;
      }
      if (entry.output !== null && LONE_SURROGATE.test(entry.output)) fail(`${where}: the output holds a lone surrogate`);
      kept.push(entry.comment === undefined ? { input: entry.input, output: entry.output } : { input: entry.input, output: entry.output, comment: entry.comment });
    }
    if (kept.length !== expectedCounts[key]) fail(`${file.path}: ${kept.length} cases selected, expected ${expectedCounts[key]}`);
    if (skip.loneSurrogate !== expectedLone[key]) fail(`${file.path}: ${skip.loneSurrogate} lone-surrogate inputs, expected ${expectedLone[key]}`);
    selected[key] = kept;
    skipped[key] = skip;
  }

  const header = {
    about:
      `web-platform-tests' url/resources/toascii.json and IdnaTestV2.json at ${WPT.commit}, the commit tr46 ${WPT.tr46Tag} ` +
      "pins in scripts/getLatestTests.mjs, selected as tr46's test/toascii.js selects them: comment strings, " +
      "urlStandardOnly cases (toascii.json), inputs holding \"?\" (IdnaTestV2.json) and all-ASCII inputs are skipped. " +
      "Inputs holding a lone surrogate are skipped too, because a Swift String can't hold one. Each case is " +
      `{input, output, comment?}, with output null for a refusal, under tr46's test/toascii.js options. Real tr46 ` +
      `${TR46.version} gives every output, which the generator asserts.`,
    license:
      "Derived from web-platform-tests, Copyright \u00a9 web-platform-tests contributors, under the 3-Clause BSD " +
      "License; the full text is in LICENSE-web-platform-tests.md next to this file. See NOTICE.",
    source: {
      commit: WPT.commit,
      files: Object.fromEntries([...Object.values(files), license].map((f) => [f.path, f.sha256])),
    },
    generator: GENERATOR,
    oracle: { tr46: { version: TR46.version, integrity: TR46.integrity } },
    counts: { toascii: selected.toascii.length, idnaTestV2: selected.idnaTestV2.length, skipped },
    options: WPT_OPTIONS,
  };
  return {
    file: `${RESOURCES}/wpt-toascii.json`,
    output: vectorFile(header, { toascii: selected.toascii, idnaTestV2: selected.idnaTestV2 }),
    summary: `toascii.json ${selected.toascii.length}, IdnaTestV2.json ${selected.idnaTestV2.length} cases`,
  };
}

// ── geospoof-idna-vectors.json ─────────────────────────────────────────────────

const SEED_COPY = `${RESOURCES}/geospoof-idna-vectors.json`;

/** GeoSpoof's hostToASCII: tr46's toASCII with the URL Standard's options, and "" read as null. */
const GEOSPOOF_OPTIONS = { checkHyphens: false, checkBidi: true, checkJoiners: true, useSTD3ASCIIRules: false, verifyDNSLength: false };

/**
 * The GeoSpoof fixture is copied, not generated: it is checked to be the pinned file, byte for
 * byte, with the pinned counts, and real tr46 is checked to give every answer in it.
 */
function checkSeedFixture({ tr46 }) {
  const bytes = readFileSync(path.join(ROOT, SEED_COPY));
  const actual = sha256(bytes);
  if (actual !== SEED_FIXTURE.sha256) {
    fail(`${SEED_COPY} has SHA-256 ${actual}, expected ${SEED_FIXTURE.sha256}; copy it again from the ${SEED_FIXTURE.origin} at ${SEED_FIXTURE.commit}`);
  }
  const fixture = JSON.parse(bytes.toString("utf8"));
  if (JSON.stringify(fixture.counts) !== JSON.stringify(SEED_FIXTURE.counts)) {
    fail(`${SEED_COPY} counts are ${JSON.stringify(fixture.counts)}, expected ${JSON.stringify(SEED_FIXTURE.counts)}`);
  }
  for (const [group, count] of Object.entries(SEED_FIXTURE.counts)) {
    if (fixture[group]?.length !== count) fail(`${SEED_COPY} has ${fixture[group]?.length} ${group} vectors, expected ${count}`);
  }
  if (fixture.tr46 !== TR46.version || fixture.mappingTableSHA256 !== TR46.members["lib/mappingTable.json"]) {
    fail(`${SEED_COPY} was not produced by tr46 ${TR46.version}`);
  }
  for (const group of Object.keys(SEED_FIXTURE.counts)) {
    for (const [index, vector] of fixture[group].entries()) {
      const result = tr46.toASCII(vector.input, GEOSPOOF_OPTIONS);
      const answer = result === "" ? null : result;
      if (answer !== vector.ascii) fail(`${SEED_COPY} ${group}[${index}] ${show(vector.input)}: tr46 gives ${show(answer)}, expected ${show(vector.ascii)}`);
    }
  }
  const total = Object.values(SEED_FIXTURE.counts).reduce((a, b) => a + b, 0);
  console.log(`[${TAG}] checked ${SEED_COPY}: SHA-256 ${actual}, ${SEED_FIXTURE.counts.curated} curated + ${SEED_FIXTURE.counts.idnaTestV2} IdnaTestV2 = ${total} vectors, all tr46's answers`);
  return fixture;
}

// ── differential.json ──────────────────────────────────────────────────────────

/** Bit j of a combination number is option j of these, in the order `TR46.Options` declares them. */
const OPTION_ORDER = {
  toASCII: ["checkHyphens", "checkBidi", "checkJoiners", "useSTD3ASCIIRules", "transitionalProcessing", "verifyDNSLength", "ignoreInvalidPunycode"],
  // tr46's toUnicode has no verifyDNSLength.
  toUnicode: ["checkHyphens", "checkBidi", "checkJoiners", "useSTD3ASCIIRules", "transitionalProcessing", "ignoreInvalidPunycode"],
};

/** Every combination of `order`, as tr46 options objects, combination k at index k. */
const combinations = (order) =>
  Array.from({ length: 2 ** order.length }, (_, k) => Object.fromEntries(order.map((name, j) => [name, (k & (2 ** j)) !== 0])));

/** A combination bitmask as fixed-width lower-case hex, bit k set for combination k. */
const hexMask = (mask, combinationCount) => mask.toString(16).padStart(combinationCount / 4, "0");

/** The longest curated input apart from the uncapped groups: 2,000 code points, plus the "xn--" of the decode-overflow case. */
const CURATED_MAX_CODE_POINTS = 2004;

/** The curated groups whose inputs have to be longer than CURATED_MAX_CODE_POINTS. */
const UNCAPPED_CURATED_GROUPS = new Set(["T8: encode overflow", "Punycode above 1,024 code points: labels that decode"]);

/**
 * The curated inputs, grouped by what they exercise. The groups overlap on
 * purpose; the inputs are deduplicated afterwards. `seedCurated` is the GeoSpoof fixture's
 * curated inputs, and `punycode` is punycode.js, for the A-label of non-NFC text.
 */
function curatedGroups(seedCurated, punycode) {
  const a = (count) => "a".repeat(count);
  const total253 = [a(63), a(63), a(63), a(61)].join(".");
  const total254 = [a(63), a(63), a(63), a(62)].join(".");
  const ascii = Array.from({ length: 0x80 }, (_, cp) => String.fromCharCode(cp));
  const cjk = String.fromCodePoint(...Array.from({ length: 1000 }, (_, i) => 0x4e00 + i));
  // Labels that decode to more than Punycode.literalLimit (1,024) code points, so the Swift port
  // decodes and re-encodes them on its O(n log n) path. The second interleaves basic code points
  // and repeats CJK code points out of order, so insertions land all over the label.
  const cjk1200 = String.fromCodePoint(...Array.from({ length: 1200 }, (_, i) => 0x4e00 + i));
  const mixed1300 = String.fromCodePoint(
    ...Array.from({ length: 1300 }, (_, i) => (i % 10 === 0 ? 0x61 + ((i / 10) % 26) : 0x4e00 + ((i * 7919) % 600)))
  );
  return [
    ["the GeoSpoof fixture's curated inputs", seedCurated],
    // The J and T items of Sources/TR46/Documentation.docc/BehaviourFromJavaScript.md, with its
    // exact strings.
    ["J1: decoded values re-pair", ["xn--8c9bk9h.com", "xn--8c9b.com", "xn--8c9bj9h.com", "xn--a-8f4gp1m.com"]],
    ["J2: a decoded value above 10FFFF", ["xn--en32g.com"]],
    ["J3: a lone surrogate in toUnicode's output", ["xn--8c9b.com"]],
    ["J5: CheckHyphens counts code points", ["\u{1F600}b--c", "ab\u{1F600}--c"]],
    ["T1: the error is sticky", ["xn--zz.xn--mnchen-3ya.de"]],
    ["T2: an xn-- label holding non-ASCII", ["xn--m\u00FCnchen.de", "xn--mnchen-3ya.xn--\u00FC.de"]],
    ["T3, T4: a label that doesn't decode, or decodes to nothing or ASCII", ["xn--zz.com", "xn--.com", "xn--a.com", "xn--a-.com"]],
    ["T5, T6: transitional processing, ẞ, and decoded labels", ["\u1E9E.de", "xn--zca.de", "fa\u00DF.de", "xn--fa-hia.de", "xn--zca.\u00DF.de"]],
    ["T7: ContextJ's earlier ZWNJ", ["\u0628\u094D\u200C\u0628\u200Ca", "\u0628\u200Ca"]],
    ["T8: encode overflow", [`${a(10950)}\u{30000}`, `${a(10900)}\u{30000}`]],
    ["T9: verifyDNSLength", [a(63), a(64), total253, total254, `${total253}.`, "", "example.com."]],
    // Edge cases by category.
    ["decode overflow", ["xn--99999999999a", "xn--zzzzzzzzzzzz", `xn--${"9".repeat(2000)}`]],
    ["DNS length edges", [a(63), a(64), total253, total254, `${total253}.`, `${total254}.`, ".", "..", "a..b"]],
    ["STD3: every ASCII character, alone and inside a?b", [...ascii, ...ascii.map((ch) => `a${ch}b`), "_dmarc.example.com"]],
    ["CheckHyphens", ["ab--c", "-a", "a-", "xn--", "xn--a-", "XN--abc", "Xn--MNCHEN-3YA"]],
    [
      "transitional: deviations, and ZWJ/ZWNJ in Indic and Arabic contexts",
      [
        "fa\u00DF.de",
        "\u1E9E.de",
        "\u03C2.gr",
        "\u0915\u094D\u200D\u0937",
        "\u0915\u094D\u200C\u0937",
        "\u0915\u200D\u0937",
        "\u0628\u0647\u200C\u0647",
        "\u0628\u200D\u0647",
        "\u0644\u064E\u200C\u0627",
      ],
    ],
    [
      "bidi",
      [
        "\u05D01\u0661.com",
        "\u06271\u0662",
        "\u05D0\u0661\u05D1",
        "\u05D01.com",
        "\u0627\u0661.com",
        "1\u05D0.com",
        "\u0661\u05D0.com",
        "a\u0301.\u05D0",
        "ab\u0300.\u05D0\u05D1",
        "xn--\u05D0.com",
      ],
    ],
    [
      "NFC",
      [
        "a\u0301",
        "\u0316\u0301",
        "\u0301\u0316",
        "a\u0316\u0301",
        "a\u0301\u0316",
        "\u1100\u1161\u11A8",
        "\uAC01",
        "\u212B",
        "\u0958",
        `xn--${punycode.encode("a\u0301")}`,
        `xn--${punycode.encode("\u0915\u093C")}`,
      ],
    ],
    [
      "emoji ZWJ sequences and full stops",
      [
        "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}.com",
        "\u{1F3F3}\uFE0F\u200D\u{1F308}.com",
        "\u{1F469}\u200D\u{1F4BB}",
        "a\u3002b",
        "a\uFF0Eb",
        "a\uFF61b",
        "example\u3002com\uFF0E",
      ],
    ],
    ["long but valid", [cjk, `${cjk}.jp`, Array(500).fill("a").join(".")]],
    ["Punycode above 1,024 code points: labels that decode", [`xn--${punycode.encode(cjk1200)}`, `xn--${punycode.encode(mixed1300)}.jp`]],
  ];
}

/**
 * Unicode's 66 noncharacters are listed in DerivedAge but are gc=Cn in every version, so they
 * are not "assigned" in the sense the newer-than-Node rule below means, and both NFCs treat them
 * as they treat any Cn.
 */
const NONCHARACTER = /^\p{Noncharacter_Code_Point}$/u;
const UNASSIGNED_IN_NODE = /^\p{Cn}$/u;

/**
 * Code points assigned in Unicode 18.0.0 (DerivedAge, less the noncharacters) that are \p{Cn}
 * under this Node, whose ICU has only Unicode 16.0. Node's normalize("NFC") could treat them
 * differently from the bundled Unicode 18.0.0 NFC, so an input that meets one is left out: the
 * newer-than-Node rule.
 * Code points unassigned in both are kept: both versions treat them identically.
 */
function newerThanNodeLookup(ageRanges) {
  const newer = new Set();
  for (const [lo, hi] of ageRanges) {
    for (let cp = lo; cp <= hi; cp++) {
      const text = String.fromCodePoint(cp);
      if (UNASSIGNED_IN_NODE.test(text) && !NONCHARACTER.test(text)) newer.add(cp);
    }
  }
  if (newer.size === 0) fail("no code point is newer than Node; is this Node's Unicode still 16.0?");
  return { size: newer.size, has: (cp) => newer.has(cp) };
}

/**
 * Every differential input (the IdnaTestV2 sources, the WPT inputs, the curated inputs and the
 * fuzz inputs), in order and deduplicated, with real tr46's answers under all 128 toASCII and 64
 * toUnicode option combinations. Each answer is grouped with the combinations
 * that give it, as a hex bitmask; the masks of one input partition the combinations.
 */
async function differentialVectors(sources, oracle, ageOf, ageRanges, seedFixture) {
  const { tr46, punycode, mapChars: map } = oracle;
  if (typeof String.prototype.toWellFormed !== "function") fail("this Node has no String.prototype.toWellFormed");
  const newer = newerThanNodeLookup(ageRanges);
  const toASCIICombinations = combinations(OPTION_ORDER.toASCII);
  const toUnicodeCombinations = combinations(OPTION_ORDER.toUnicode);
  const allASCII = (1n << BigInt(toASCIICombinations.length)) - 1n;
  const allUnicode = (1n << BigInt(toUnicodeCombinations.length)) - 1n;

  /** Groups per-combination answers by `key`, in order of each answer's first combination. */
  const group = (answers, key) => {
    const groups = new Map();
    answers.forEach((answer, k) => {
      const id = key(answer);
      if (!groups.has(id)) groups.set(id, { answer, mask: 0n });
      groups.get(id).mask |= 1n << BigInt(k);
    });
    return [...groups.values()];
  };
  const checkPartition = (groups, all, where) => {
    let union = 0n;
    for (const { mask } of groups) {
      if ((union & mask) !== 0n) fail(`${where}: two answers claim the same combination`);
      union |= mask;
    }
    if (union !== all) fail(`${where}: the answers don't cover every combination`);
  };

  /** The vector for `input`, or null when the newer-than-Node rule leaves it out. */
  const vectorFor = (input, where) => {
    if (LONE_SURROGATE.test(input)) fail(`${where} ${show(input)}: a lone surrogate in an input`);
    const ascii = toASCIICombinations.map((options) => tr46.toASCII(input, options));
    const unicode = toUnicodeCombinations.map((options) => tr46.toUnicode(input, options));
    // The input, both mapped intermediates and every answer: whatever tr46 normalizes, or checks
    // is normalized, is one of these or is built from them.
    const texts = new Set([input, map(input, false), map(input, true)]);
    for (const value of ascii) if (value !== null) texts.add(value);
    for (const { domain } of unicode) texts.add(domain);
    const codePoints = [...texts].flatMap(codePointsOf);
    if (codePoints.some((cp) => newer.has(cp))) return null;

    const asciiGroups = group(ascii, (value) => (value === null ? "null" : `"${value}`));
    checkPartition(asciiGroups, allASCII, `${where} toASCII`);
    const toASCII = asciiGroups.map(({ answer, mask }) => [answer, hexMask(mask, toASCIICombinations.length)]);
    for (const value of ascii) {
      if (value !== null && LONE_SURROGATE.test(value)) fail(`${where} ${show(input)}: toASCII gives a lone surrogate`);
    }
    // J3: a Swift String can't hold a lone surrogate, so a domain with one is compared as
    // toWellFormed() gives it, U+FFFD in its place, and marked. tr46 only ever gives one with an error.
    const wellFormed = unicode.map(({ domain, error }) => {
      const replaced = domain.toWellFormed();
      if (replaced === domain) return [domain, error];
      if (error !== true) fail(`${where} ${show(input)}: toUnicode gives a lone surrogate without an error`);
      return [replaced, error, true];
    });
    const unicodeGroups = group(wellFormed, (answer) => JSON.stringify(answer));
    checkPartition(unicodeGroups, allUnicode, `${where} toUnicode`);
    const toUnicode = unicodeGroups.map(({ answer: [domain, error, replaced], mask }) => {
      const row = [domain, error, hexMask(mask, toUnicodeCombinations.length)];
      if (replaced) row.push(true);
      return row;
    });

    const vector = { input, toASCII, toUnicode };
    const age = ageAboveFloor(ageOf, codePoints);
    if (age !== null) vector.age = age;
    return vector;
  };

  const seen = new Set();
  const vectors = [];
  const counts = { inputs: 0, idnaTestV2: 0, wpt: 0, curated: 0, fuzz: 0, excludedNewerThanNode: 0, toASCIIResults: 0, toUnicodeResults: 0 };
  const excluded = { idnaTestV2: 0, wpt: 0, curated: 0, fuzz: 0 };
  const duplicates = { idnaTestV2: 0, wpt: 0, curated: 0, fuzz: 0 };
  /** Adds `input` from `kind` unless it is a duplicate or the newer-than-Node rule leaves it out;
   * returns whether it did. */
  const add = (kind, input, where) => {
    if (seen.has(input)) {
      duplicates[kind]++;
      return false;
    }
    seen.add(input);
    const vector = vectorFor(input, where);
    if (vector === null) {
      excluded[kind]++;
      counts.excludedNewerThanNode++;
      return false;
    }
    vectors.push(vector);
    counts[kind]++;
    return true;
  };

  // 1. Every IdnaTestV2 source except the two with a lone surrogate (J4).
  const idna = await sources.unicode("IdnaTestV2");
  let idnaLone = 0;
  for (const row of parseIdnaTestV2(idna.text)) {
    if (LONE_SURROGATE.test(row.source)) {
      idnaLone++;
      continue;
    }
    add("idnaTestV2", row.source, `IdnaTestV2.txt:${row.line}`);
  }
  if (idnaLone !== 2) fail(`IdnaTestV2.txt has ${idnaLone} lone-surrogate sources, expected 2`);

  // 2. Every WPT input, the ones tr46's harness skips included, except the two with a lone surrogate.
  let wptLone = 0;
  for (const key of ["toascii", "idnaTestV2"]) {
    const file = await sources.wpt(key);
    for (const [index, entry] of JSON.parse(file.text).entries()) {
      if (typeof entry === "string") continue; // a comment
      if (LONE_SURROGATE.test(entry.input)) {
        wptLone++;
        continue;
      }
      add("wpt", entry.input, `${file.path}[${index}]`);
    }
  }
  if (wptLone !== 2) fail(`the WPT files have ${wptLone} lone-surrogate inputs, expected 2`);

  // 3. The curated inputs.
  const seedCurated = seedFixture.curated.map((vector) => vector.input);
  if (seedCurated.length !== SEED_FIXTURE.counts.curated) fail(`the GeoSpoof fixture has ${seedCurated.length} curated inputs`);
  for (const [note, inputs] of curatedGroups(seedCurated, punycode)) {
    for (const input of inputs) {
      const length = codePointsOf(input).length;
      if (length > CURATED_MAX_CODE_POINTS && !UNCAPPED_CURATED_GROUPS.has(note)) fail(`curated "${note}": an input of ${length} code points`);
      add("curated", input, `curated "${note}"`);
    }
  }

  // 4. Exactly FUZZ_COUNT fuzz inputs. A draw that repeats an earlier input, or that the
  // newer-than-Node rule leaves out, is replaced by the next one.
  const pkg = oracle.pkg;
  const unicodeData = parseUnicodeData((await sources.unicode("UnicodeData")).text);
  const pools = createPools({ rows: oracle.rows, status: oracle.status, classes: readClasses(pkg), unicodeData, newerThanNode: newer.has });
  const nextFuzz = createFuzzer({ random: createRandom(FUZZ_SEED), pools, punycode });
  let drawn = 0;
  while (counts.fuzz < FUZZ_COUNT) {
    if (++drawn > FUZZ_COUNT * 2) fail(`only ${counts.fuzz} of ${FUZZ_COUNT} fuzz inputs after ${drawn} draws`);
    add("fuzz", nextFuzz(), `fuzz draw ${drawn}`);
  }

  counts.inputs = vectors.length;
  counts.toASCIIResults = vectors.length * toASCIICombinations.length;
  counts.toUnicodeResults = vectors.length * toUnicodeCombinations.length;
  if (counts.idnaTestV2 + counts.wpt + counts.curated + counts.fuzz !== counts.inputs) fail("the per-source counts don't add up");
  const withAge = vectors.filter((vector) => vector.age !== undefined).length;
  const replaced = vectors.filter((vector) => vector.toUnicode.some((row) => row.length === 4)).length;

  const header = {
    about:
      `Real tr46 ${TR46.version}'s answers under Node ${NODE.version}, for every combination of its options: all 128 for ` +
      "toASCII and all 64 for toUnicode, which has no verifyDNSLength. Combination k has option optionOrder[j] on when bit j " +
      "of k is set. The inputs are every IdnaTestV2.txt source, every WPT toascii.json and IdnaTestV2.json input (the ones " +
      "tr46's harness skips included), the curated inputs of Scripts/generate-vectors.mjs and seeded fuzz inputs from " +
      "Scripts/lib/fuzz.mjs, deduplicated, less the ones holding a lone surrogate, which a Swift String can't hold. An input " +
      "is left out (excludedNewerThanNode) when it, either of its mapped forms or any answer holds a code point assigned in " +
      `Unicode ${UNICODE.version} that this Node's Unicode ${NODE.unicode} leaves unassigned, because there Node's NFC may ` +
      "legitimately differ. Each vector is {input, toASCII: [[answer or null, mask], ...], toUnicode: [[domain, error, mask, " +
      "replacedLoneSurrogates?], ...], age?}. A mask is hex, bit k for combination k, and the masks of one vector partition " +
      "the combinations. A toUnicode domain is given as toWellFormed() gives it, with replacedLoneSurrogates true where that " +
      `replaced a lone surrogate by U+FFFD. age is the highest DerivedAge among the assigned code points of the input, its ` +
      `mapped forms and the answers, present only above ${AGE_FLOOR}; the .foundation comparison skips those vectors.`,
    license:
      "The curated and fuzz inputs are this package's, under its MIT License (LICENSE). The IdnaTestV2 inputs are derived " +
      `from Unicode's IdnaTestV2.txt ${UNICODE.version}, Copyright \u00a9 1991-2026 Unicode, Inc., under the Unicode ` +
      "License V3 (https://www.unicode.org/license.txt). The WPT inputs are derived from web-platform-tests, Copyright " +
      "\u00a9 web-platform-tests contributors, under the 3-Clause BSD License; the full text is in " +
      "LICENSE-web-platform-tests.md next to this file. See NOTICE.",
    source: {
      unicode: { version: UNICODE.version, files: { [idna.path]: { url: idna.url, sha256: idna.sha256 } } },
      wpt: { commit: WPT.commit, files: Object.fromEntries(["toascii", "idnaTestV2"].map((key) => [WPT.files[key].path, WPT.files[key].sha256])) },
    },
    generator: GENERATOR,
    tr46: { version: TR46.version, integrity: TR46.integrity },
    punycode: { version: PUNYCODE.version, integrity: PUNYCODE.integrity },
    node: { version: process.version, unicode: process.versions.unicode, icu: process.versions.icu },
    fuzzSeed: `0x${FUZZ_SEED.toString(16)}`,
    optionOrder: OPTION_ORDER,
    counts,
  };
  console.log(
    `[${TAG}] differential: ${drawn} fuzz draws; duplicates ${JSON.stringify(duplicates)}; excluded newer than Node ` +
      `${JSON.stringify(excluded)} (${newer.size} code points are newer than Node); ${withAge} with an age above ` +
      `${AGE_FLOOR}; ${replaced} with a replaced lone surrogate`
  );
  return {
    file: `${RESOURCES}/differential.json`,
    output: vectorFile(header, { vectors }),
    summary:
      `${counts.inputs} inputs (IdnaTestV2 ${counts.idnaTestV2}, WPT ${counts.wpt}, curated ${counts.curated}, fuzz ${counts.fuzz}; ` +
      `${counts.excludedNewerThanNode} excluded newer than Node), ${counts.toASCIIResults} toASCII and ${counts.toUnicodeResults} toUnicode results`,
  };
}

// ── Main ───────────────────────────────────────────────────────────────────────

await run(TAG, async () => {
  const options = parseArgs(process.argv.slice(2));
  const sources = new Sources(options);
  if (options.fetchOnly) {
    await sources.fetchAll();
    return;
  }
  const age = await sources.unicode("DerivedAge");
  const ageRanges = parseDerivedAge(age.text);
  const ageOf = ageLookup(ageRanges);
  const tr46 = loadTr46(sources);
  // Every section is computed, and so every assertion run, before any file is written.
  const seedFixture = checkSeedFixture(tr46);
  const outputs = [
    await normalizationVectors(sources),
    await idnaTestV2Vectors(sources, tr46, ageOf),
    await wptVectors(sources, tr46),
    await differentialVectors(sources, tr46, ageOf, ageRanges, seedFixture),
  ];
  for (const { file, output, summary } of outputs) writeOutput(TAG, file, output, summary);
});
