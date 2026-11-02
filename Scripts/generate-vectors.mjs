/**
 * generate-vectors.mjs
 *
 * Writes the test data in Tests/TR46Tests/Resources, one section per file:
 *   normalizationVectors()   normalization-test.json   Unicode 18.0.0's NormalizationTest.txt
 *
 *   Scripts/regenerate.sh           # both generators (preferred)
 *   node Scripts/generate-vectors.mjs [--unicode-dir d] [--data-dir d] [--tr46-tarball p] [--punycode-tarball p]
 *
 * Raw upstream files are never committed. Each one is read through Scripts/lib/sources.mjs,
 * verified by hash, and re-encoded as deterministic JSON: one vector per line, with every UTF-16
 * unit above U+007E written as a \uXXXX escape, so no tool can renormalize the data. Every count
 * a file promises is asserted here.
 */
import { Sources, UNICODE, fail, parseArgs, run } from "./lib/sources.mjs";
import { ageLookup, ageRank, parseDerivedAge, parseNormalizationTest } from "./lib/ucd.mjs";
import { vectorFile, writeOutput } from "./lib/emit.mjs";

const TAG = "generate-vectors";
const RESOURCES = "Tests/TR46Tests/Resources";
const GENERATOR = "Scripts/regenerate.sh";

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

// ── Main ───────────────────────────────────────────────────────────────────────

await run(TAG, async () => {
  const options = parseArgs(process.argv.slice(2));
  const sources = new Sources(options);
  if (options.fetchOnly) {
    await sources.fetchAll();
    return;
  }
  // Every section is computed, and so every assertion run, before any file is written.
  const outputs = [await normalizationVectors(sources)];
  for (const { file, output, summary } of outputs) writeOutput(TAG, file, output, summary);
});
