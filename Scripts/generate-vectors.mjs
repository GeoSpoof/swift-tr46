/**
 * generate-vectors.mjs
 *
 * Writes the test data in Tests/TR46Tests/Resources, one section per file:
 *   normalizationVectors()   normalization-test.json   Unicode 18.0.0's NormalizationTest.txt
 *   idnaTestV2Vectors()      idna-test-v2.json         Unicode 18.0.0's IdnaTestV2.txt, resolved strictly
 *   wptVectors()             wpt-toascii.json          WPT toascii.json and IdnaTestV2.json at tr46's pin
 *   checkSeedFixture()       (writes nothing)          geospoof-idna-vectors.json, copied verbatim, is checked
 *
 * Every expected IDNA answer is checked against real tr46 7.0.0 from the verified tarball, and the
 * run fails on the first one tr46 doesn't give.
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
import { ROOT, SEED_FIXTURE, Sources, TR46, UNICODE, WPT, fail, parseArgs, run, sha256 } from "./lib/sources.mjs";
import {
  ageLookup,
  ageRank,
  parseDerivedAge,
  parseIdnaStatus,
  parseIdnaTestV2,
  parseNormalizationTest,
} from "./lib/ucd.mjs";
import { mapChars, readMappingTable, readStatusMapping } from "./lib/tr46-data.mjs";
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
 * IdnaTestV2.txt, each row resolved strictly by the file's own rules (plan.md D7), and every
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
  const ageOf = ageLookup(parseDerivedAge(age.text));
  const tr46 = loadTr46(sources);
  // Every section is computed, and so every assertion run, before any file is written.
  const outputs = [
    await normalizationVectors(sources),
    await idnaTestV2Vectors(sources, tr46, ageOf),
    await wptVectors(sources, tr46),
  ];
  checkSeedFixture(tr46);
  for (const { file, output, summary } of outputs) writeOutput(TAG, file, output, summary);
});
