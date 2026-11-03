/**
 * generate-tables.mjs
 *
 * Writes the two generated Swift files:
 *   Sources/TR46/Generated/IDNATables.swift   tr46 7.0.0's mappingTable.json and regexes.js, re-encoded
 *   Sources/TR46/Generated/NFCTables.swift    Unicode 18.0.0's canonical normalization data
 *
 *   Scripts/regenerate.sh           # both generators (preferred)
 *   node Scripts/generate-tables.mjs [--tr46-tarball p] [--punycode-tarball p] [--unicode-dir d] [--data-dir d]
 *   node Scripts/generate-tables.mjs --fetch-only
 *
 * Every input comes from Scripts/lib/sources.mjs, verified by hash. Every assumption the Swift
 * code makes about the data is asserted here, and a failed assertion exits 1 without writing
 * anything. Before NFCTables.swift is written, a JavaScript NFC built only from the packed arrays
 * must pass every NormalizationTest 18.0.0 invariant, and must agree with Node's own NFC on every
 * test string Node's Unicode version can represent. The output carries no timestamps, so the same
 * inputs give byte-identical files.
 */
import { PUNYCODE, Sources, TR46, UNICODE, fail, parseArgs, run } from "./lib/sources.mjs";
import {
  parseCompositionExclusions,
  parseDerivedNormalizationProps,
  parseNormalizationTest,
  parseUnicodeData,
} from "./lib/ucd.mjs";
import { CLASS_DOCS, inRanges, mergeRuns, readClasses, readMappingTable, readStatusMapping, rowAt } from "./lib/tr46-data.mjs";
import { UNICODE_LICENSE_V3, swiftArray, swiftComment, swiftString, writeOutput } from "./lib/emit.mjs";

const TAG = "generate-tables";
const U = (cp) => `U+${cp.toString(16).toUpperCase().padStart(4, "0")}`;

// ── IDNATables.swift ───────────────────────────────────────────────────────────

function idnaTables(sources) {
  const { tr46, punycode } = sources.packages();
  const status = readStatusMapping(tr46);
  const rows = readMappingTable(tr46, status);
  const statusAt = (cp) => rowAt(rows, cp).status;

  // TableLookup and the port rely on each of these.
  for (let cp = 0xd800; cp <= 0xdfff; cp++) {
    if (statusAt(cp) !== status.disallowed) fail(`${U(cp)} is not disallowed; validateLabel's lone-surrogate rule relies on it`);
  }
  if (statusAt(0x2e) !== status.valid) fail("U+002E is not valid; the port splits on it after mapping");

  // Transitional processing reads the deviation mappings, so all three are kept, and pinned.
  const deviations = rows.filter((row) => row.status === status.deviation).map((row) => [row.lo, row.hi, row.mapping]);
  const expectedDeviations = [[0xdf, 0xdf, "ss"], [0x3c2, 0x3c2, "\u03c3"], [0x200c, 0x200d, ""]];
  if (JSON.stringify(deviations) !== JSON.stringify(expectedDeviations)) {
    fail(`deviation rows are ${JSON.stringify(deviations)}, expected ${JSON.stringify(expectedDeviations)}`);
  }
  const capitalSharpS = rowAt(rows, 0x1e9e);
  if (capitalSharpS.status !== status.mapped || capitalSharpS.mapping !== "\u00df") {
    fail(`U+1E9E is ${capitalSharpS.status} → ${JSON.stringify(capitalSharpS.mapping)}, expected mapped to U+00DF`);
  }

  // ASCII fast path: the ASCII branch of mapChars lower-cases A–Z and keeps everything else.
  for (let cp = 0; cp <= 0x7f; cp++) {
    const row = rowAt(rows, cp);
    if (cp >= 0x41 && cp <= 0x5a) {
      if (row.status !== status.mapped || row.mapping !== String.fromCharCode(cp + 0x20)) {
        fail(`${U(cp)} is not mapped to its lower case; the ASCII fast path relies on it`);
      }
    } else if (row.status !== status.valid || row.mapping !== undefined) {
      fail(`${U(cp)} has status ${row.status}, expected valid; the ASCII fast path relies on it`);
    }
  }

  const runs = mergeRuns(rows);
  const pool = [];
  const poolOffsets = new Map();
  const entries = runs.map((r) => {
    let offset = 0;
    if (r.scalars.length > 0) {
      const key = r.scalars.join(",");
      if (!poolOffsets.has(key)) {
        poolOffsets.set(key, pool.length);
        pool.push(...r.scalars);
      }
      offset = poolOffsets.get(key);
    }
    if (r.scalars.length >= 32) fail(`a mapping of ${r.scalars.length} scalars doesn't fit 5 bits`);
    if (offset >= 1 << 24) fail(`a pool offset of ${offset} doesn't fit 24 bits`);
    return (r.status | (r.scalars.length << 3) | (offset << 8)) >>> 0;
  });
  for (const scalar of pool) {
    if (scalar >= 0xd800 && scalar <= 0xdfff) fail(`a surrogate ${U(scalar)} in the mapping pool`);
  }

  // The packed table answers exactly what mappingTable.json does, for every code point.
  const starts = runs.map((r) => r.start);
  for (let cp = 0, run = 0; cp <= 0x10ffff; cp++) {
    while (run + 1 < starts.length && starts[run + 1] <= cp) run++;
    const entry = entries[run];
    const length = (entry >>> 3) & 0x1f;
    const offset = entry >>> 8;
    const row = rowAt(rows, cp);
    if ((entry & 7) !== row.status || pool.slice(offset, offset + length).join(",") !== row.scalars.join(",")) {
      fail(`the packed table disagrees with mappingTable.json at ${U(cp)}`);
    }
  }

  const classes = readClasses(tr46);
  const ranges = Object.fromEntries(classes.map((t) => [t.swiftName, t.ranges]));
  const zwnjClasses = ["validZWNJBefore", "validZWNJTransparentBefore", "validZWNJTransparentAfter", "validZWNJAfter"];
  // ASCII fast path: an all-ASCII label skips the combining-mark and ContextJ steps, and an all-ASCII domain
  // is never a Bidi domain name, so none of these classes may hold an ASCII code point.
  for (const name of ["combiningMarks", "combiningClassVirama", ...zwnjClasses, "bidiDomain"]) {
    if (ranges[name].length > 0 && ranges[name][0][0] <= 0x7f) fail(`${name} contains ASCII ${U(ranges[name][0][0])}`);
  }
  // The ContextJ port scans for the joiners themselves; a class holding one would change that scan.
  for (const name of zwnjClasses) {
    for (const joiner of [0x200c, 0x200d]) {
      if (inRanges(ranges[name], joiner)) fail(`${name} contains ${U(joiner)}`);
    }
  }
  for (const name of ["validZWNJTransparentBefore", "validZWNJTransparentAfter"]) {
    if (inRanges(ranges[name], 0x200c)) fail(`${name} contains U+200C`);
  }

  const classRanges = classes.reduce((n, t) => n + t.ranges.length, 0);
  const tr46License = tr46.read("LICENSE.md").toString("utf8");
  const header = `// GENERATED by Scripts/generate-tables.mjs, do not edit.
//   Regenerate: Scripts/regenerate.sh
//   Check:      Scripts/regenerate.sh --check
//
// tr46 ${TR46.version} (UTS #46 data for Unicode ${TR46.unicodeVersion}) and punycode.js ${PUNYCODE.version}, from the npm tarballs
//   ${TR46.name}-${TR46.version}.tgz       ${TR46.integrity}
//   ${PUNYCODE.name}-${PUNYCODE.version}.tgz   ${PUNYCODE.integrity}
// SHA-256 of the files these tables come from, or that the port follows:
//   tr46/index.js                ${tr46.members["index.js"]}
//   tr46/lib/mappingTable.json   ${tr46.members["lib/mappingTable.json"]}
//   tr46/lib/regexes.js          ${tr46.members["lib/regexes.js"]}
//   tr46/lib/statusMapping.js    ${tr46.members["lib/statusMapping.js"]}
//   punycode/punycode.js         ${punycode.members["punycode.js"]}
//
// ${runs.length} mapping runs, ${pool.length} mapping scalars, ${classRanges} class ranges.
//
// The tables are tr46's lib/mappingTable.json and lib/regexes.js, re-encoded. tr46's notice:
//
${swiftComment(tr46License)}
//
// tr46's data is derived from Unicode data files. Their notice (https://www.unicode.org/license.txt):
//
${swiftComment(UNICODE_LICENSE_V3)}
`;

  const body = [
    swiftString("tr46Version", TR46.version),
    swiftString("tr46UnicodeVersion", TR46.unicodeVersion),
    swiftString("punycodeVersion", PUNYCODE.version),
    swiftString("indexSHA256", tr46.members["index.js"]),
    swiftString("mappingTableSHA256", tr46.members["lib/mappingTable.json"]),
    swiftString("regexesSHA256", tr46.members["lib/regexes.js"]),
    swiftString("statusMappingSHA256", tr46.members["lib/statusMapping.js"]),
    swiftString("punycodeSHA256", punycode.members["punycode.js"]),
    "",
    swiftArray("The first code point of each run. A run ends where the next begins; starts[0] is 0.", "starts", "UInt32", starts),
    "",
    swiftArray(
      "One per run: bits 0–2 tr46's status, bits 3–7 the mapping's length, bits 8–31 its offset in mappingScalars.",
      "entries",
      "UInt32",
      entries
    ),
    "",
    swiftArray("Every distinct mapping, deviations included, concatenated in order of first use.", "mappingScalars", "UInt32", pool),
    ...classes.flatMap((t) => [
      "",
      swiftArray(`${CLASS_DOCS[t.swiftName]} Sorted inclusive [lo, hi] pairs.`, t.swiftName, "UInt32", t.ranges.flat()),
    ]),
  ].join("\n");

  const output = `${header}
/// tr46 ${TR46.version}'s mapping table and regex classes. Data only: the lookups are in TableLookup.swift.
internal enum IDNATables {
${body}
}
`;
  return { output, summary: `${runs.length} runs, ${pool.length} mapping scalars, ${classRanges} class ranges` };
}

// ── NFCTables.swift ────────────────────────────────────────────────────────────

const HANGUL = { SBase: 0xac00, LBase: 0x1100, VBase: 0x1161, TBase: 0x11a7, LCount: 19, VCount: 21, TCount: 28 };
HANGUL.NCount = HANGUL.VCount * HANGUL.TCount;
HANGUL.SCount = HANGUL.LCount * HANGUL.NCount;
const isHangulSyllable = (cp) => cp >= HANGUL.SBase && cp < HANGUL.SBase + HANGUL.SCount;
const isSurrogate = (cp) => cp >= 0xd800 && cp <= 0xdfff;

/** Sorted, merged inclusive ranges. */
function mergeRanges(ranges) {
  const sorted = [...ranges].sort((a, b) => a[0] - b[0]);
  const merged = [];
  for (const [lo, hi] of sorted) {
    const last = merged[merged.length - 1];
    if (last && lo <= last[1] + 1) last[1] = Math.max(last[1], hi);
    else merged.push([lo, hi]);
  }
  return merged;
}

const expandRanges = (ranges) => ranges.flatMap(([lo, hi]) => Array.from({ length: hi - lo + 1 }, (_, i) => lo + i));
const sameArray = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const COMPOSITION_SHIFT = 2 ** 21;

async function nfcTables(sources) {
  const files = {};
  for (const key of ["UnicodeData", "CompositionExclusions", "DerivedNormalizationProps", "NormalizationTest"]) {
    files[key] = await sources.unicode(key);
  }
  for (const key of ["CompositionExclusions", "DerivedNormalizationProps", "NormalizationTest"]) {
    if (!files[key].text.startsWith(`# ${key}-${UNICODE.version}.txt\n`)) fail(`${files[key].path} is not version ${UNICODE.version}`);
  }

  // ── UnicodeData: combining classes and canonical decompositions
  const entries = parseUnicodeData(files.UnicodeData.text);
  const ccc = new Map();
  const canonical = new Map();
  let hangulRange = null;
  for (const e of entries) {
    if (e.first !== e.last) {
      if (e.ccc !== 0 || e.decomposition) fail(`the range ${e.name} has a combining class or a decomposition`);
      if (e.name === "<Hangul Syllable>") hangulRange = [e.first, e.last];
      continue;
    }
    if (e.ccc !== 0) ccc.set(e.first, e.ccc);
    if (e.decomposition && e.decompositionTag === null) canonical.set(e.first, e.decomposition);
  }
  // The algorithmic Hangul path covers exactly what the UCD calls Hangul syllables.
  if (JSON.stringify(hangulRange) !== JSON.stringify([HANGUL.SBase, HANGUL.SBase + HANGUL.SCount - 1])) {
    fail(`the Hangul syllable range is ${JSON.stringify(hangulRange)}, expected AC00..D7A3`);
  }
  const cccOf = (cp) => ccc.get(cp) ?? 0;
  for (const [cp, d] of canonical) {
    if (d.length < 1 || d.length > 2) fail(`${U(cp)}'s canonical decomposition has ${d.length} code points`);
    if (isHangulSyllable(cp) || isSurrogate(cp)) fail(`${U(cp)} has a table decomposition`);
  }

  // ── Full recursive decompositions, packed
  const full = new Map();
  const expand = (cp) => {
    const d = canonical.get(cp);
    if (!d) return [cp];
    if (!full.has(cp)) full.set(cp, d.flatMap(expand));
    return full.get(cp);
  };
  const decompositionKeys = [...canonical.keys()].sort((a, b) => a - b);
  const decompositionPool = [];
  const decompositionEntries = decompositionKeys.map((cp) => {
    const sequence = expand(cp);
    if (sequence.length > 7) fail(`${U(cp)} decomposes to ${sequence.length} code points; entries hold at most 7`);
    for (const part of sequence) {
      if (isHangulSyllable(part)) fail(`${U(cp)} decomposes to the Hangul syllable ${U(part)}`);
      if (isSurrogate(part)) fail(`${U(cp)} decomposes to a surrogate`);
    }
    const offset = decompositionPool.length;
    if (offset >= 2 ** 29) fail("the decomposition pool doesn't fit 29 bits");
    decompositionPool.push(...sequence);
    return ((offset << 3) | sequence.length) >>> 0;
  });

  // ── Full_Composition_Exclusion: derive it, then require the UCD's own list to agree
  const props = parseDerivedNormalizationProps(files.DerivedNormalizationProps.text);
  const listed = parseCompositionExclusions(files.CompositionExclusions.text);
  const derived = new Set(listed);
  for (const [cp, d] of canonical) {
    if (d.length === 1) derived.add(cp); // singleton
    else if (cccOf(d[0]) !== 0) derived.add(cp); // non-starter decomposition
  }
  const official = new Set(expandRanges(props.get("Full_Composition_Exclusion") ?? []));
  const onlyDerived = [...derived].filter((cp) => !official.has(cp));
  const onlyOfficial = [...official].filter((cp) => !derived.has(cp));
  if (official.size === 0 || onlyDerived.length > 0 || onlyOfficial.length > 0) {
    fail(
      `Full_Composition_Exclusion differs: derived only ${onlyDerived.map(U).join(" ") || "none"}; ` +
        `DerivedNormalizationProps only ${onlyOfficial.map(U).join(" ") || "none"}`
    );
  }

  // ── Primary composites
  const compositions = new Map();
  for (const [cp, d] of canonical) {
    if (d.length !== 2 || official.has(cp)) continue;
    const key = d[0] * COMPOSITION_SHIFT + d[1];
    if (compositions.has(key)) fail(`${U(d[0])} ${U(d[1])} composes to both ${U(compositions.get(key))} and ${U(cp)}`);
    compositions.set(key, cp);
  }
  const compositionKeys = [...compositions.keys()].sort((a, b) => a - b);
  const compositionValues = compositionKeys.map((key) => compositions.get(key));

  // ── Quick check
  const qcNo = mergeRanges(props.get("NFC_QC=N") ?? []);
  const qcMaybe = mergeRanges(props.get("NFC_QC=M") ?? []);
  if (qcNo.length === 0 || qcMaybe.length === 0) fail("DerivedNormalizationProps has no NFC_QC ranges");
  for (const [lo, hi] of qcNo) {
    for (let cp = lo; cp <= hi; cp++) if (inRanges(qcMaybe, cp)) fail(`${U(cp)} is both NFC_QC=N and NFC_QC=M`);
  }

  // ── ASCII fast path: an all-ASCII string is already NFC
  for (let cp = 0; cp <= 0x7f; cp++) {
    if (cccOf(cp) !== 0) fail(`${U(cp)} has combining class ${cccOf(cp)}`);
    if (entries.some((e) => e.first === cp && e.decomposition)) fail(`${U(cp)} has a decomposition`);
    if (inRanges(qcNo, cp) || inRanges(qcMaybe, cp)) fail(`${U(cp)} is not NFC_QC=Y`);
  }
  for (const key of compositionKeys) {
    const first = Math.floor(key / COMPOSITION_SHIFT);
    const second = key % COMPOSITION_SHIFT;
    if (first <= 0x7f && second <= 0x7f) fail(`${U(first)} ${U(second)} compose, both ASCII`);
  }

  // ── Combining class runs over 0…10FFFF
  const cccStarts = [];
  const cccValues = [];
  for (let cp = 0; cp <= 0x10ffff; cp++) {
    const value = cccOf(cp);
    if (cccValues.length === 0 || cccValues[cccValues.length - 1] !== value) {
      cccStarts.push(cp);
      cccValues.push(value);
    }
  }

  const packed = {
    cccStarts,
    cccValues,
    decompositionKeys,
    decompositionEntries,
    decompositionPool,
    compositionKeys,
    compositionValues,
    quickCheckNo: qcNo.flat(),
    quickCheckMaybe: qcMaybe.flat(),
  };
  const selfTest = nfcSelfTest(packed, parseNormalizationTest(files.NormalizationTest.text));
  console.log(`[${TAG}] JS NFC self-test over the packed tables: ${selfTest}`);

  const header = `// GENERATED by Scripts/generate-tables.mjs, do not edit.
//   Regenerate: Scripts/regenerate.sh
//   Check:      Scripts/regenerate.sh --check
//
// Canonical normalization data for Unicode ${UNICODE.version}, from the Unicode Character Database
// (${UNICODE.baseURL}ucd/). SHA-256 of the files it comes from:
//   ${files.UnicodeData.path}                 ${files.UnicodeData.sha256}
//   ${files.CompositionExclusions.path}       ${files.CompositionExclusions.sha256}
//   ${files.DerivedNormalizationProps.path}   ${files.DerivedNormalizationProps.sha256}
// Before this file was written, an NFC built from these arrays passed every NFC invariant of
//   ${files.NormalizationTest.path}           ${files.NormalizationTest.sha256}
//
// ${cccStarts.length} combining-class runs, ${decompositionKeys.length} decompositions (${decompositionPool.length} pool scalars), ${compositionKeys.length} primary composites,
// ${qcNo.length} NFC_QC=No and ${qcMaybe.length} NFC_QC=Maybe ranges.
//
// Unicode's notice (https://www.unicode.org/license.txt):
//
${swiftComment(UNICODE_LICENSE_V3)}
`;

  const body = [
    swiftString("unicodeVersion", UNICODE.version),
    swiftString("unicodeDataSHA256", files.UnicodeData.sha256),
    swiftString("compositionExclusionsSHA256", files.CompositionExclusions.sha256),
    swiftString("derivedNormalizationPropsSHA256", files.DerivedNormalizationProps.sha256),
    "",
    swiftArray("The first code point of each Canonical_Combining_Class run. cccStarts[0] is 0.", "cccStarts", "UInt32", cccStarts),
    "",
    swiftArray("The Canonical_Combining_Class of each run.", "cccValues", "UInt8", cccValues),
    "",
    swiftArray("Code points with a canonical decomposition, sorted. Hangul syllables are not here.", "decompositionKeys", "UInt32", decompositionKeys),
    "",
    swiftArray(
      "One per key: bits 0–2 the full decomposition's length, bits 3–31 its offset in decompositionPool.",
      "decompositionEntries",
      "UInt32",
      decompositionEntries
    ),
    "",
    swiftArray("Full recursive canonical decompositions, concatenated in key order.", "decompositionPool", "UInt32", decompositionPool),
    "",
    swiftArray(
      "Primary composite pairs as first << 21 | second, sorted. Full_Composition_Exclusion and Hangul are not here.",
      "compositionKeys",
      "UInt64",
      compositionKeys
    ),
    "",
    swiftArray("The primary composite of each pair in compositionKeys.", "compositionValues", "UInt32", compositionValues),
    "",
    swiftArray("NFC_QC=No. Sorted inclusive [lo, hi] pairs.", "quickCheckNo", "UInt32", packed.quickCheckNo),
    "",
    swiftArray("NFC_QC=Maybe. Sorted inclusive [lo, hi] pairs.", "quickCheckMaybe", "UInt32", packed.quickCheckMaybe),
  ].join("\n");

  const output = `${header}
/// Unicode ${UNICODE.version}'s canonical normalization data, for the bundled NFC in Normalization.swift.
/// Data only. Hangul syllables are composed and decomposed algorithmically and appear in no table.
internal enum NFCTables {
${body}
}
`;
  const summary =
    `${cccStarts.length} ccc runs, ${decompositionKeys.length} decompositions, ${decompositionPool.length} pool scalars, ` +
    `${compositionKeys.length} composites, ${qcNo.length}+${qcMaybe.length} quick-check ranges`;
  return { output, summary };
}

// ── The JavaScript NFC self-test ───────────────────────────────────────────────

/**
 * An NFC that reads only the packed arrays, the same way Normalization.swift does (UAX #15:
 * quick check, full decomposition with algorithmic Hangul, stable canonical reordering, the
 * sample composition algorithm). Returns { normalize, decomposeAndCompose, quickCheck }.
 */
function packedNFC(t) {
  const { SBase, LBase, VBase, TBase, LCount, VCount, TCount, SCount } = HANGUL;
  const lastAtOrBelow = (starts, cp) => {
    let lo = 0;
    let hi = starts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= cp) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  };
  const exact = (keys, key) => {
    let lo = 0;
    let hi = keys.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (keys[mid] < key) lo = mid + 1;
      else if (keys[mid] > key) hi = mid - 1;
      else return mid;
    }
    return -1;
  };
  const inPairs = (pairs, cp) => {
    let lo = 0;
    let hi = pairs.length / 2 - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (cp < pairs[2 * mid]) hi = mid - 1;
      else if (cp > pairs[2 * mid + 1]) lo = mid + 1;
      else return true;
    }
    return false;
  };
  const cccOf = (cp) => t.cccValues[lastAtOrBelow(t.cccStarts, cp)];

  const quickCheck = (cps) => {
    let lastClass = 0;
    let result = "yes";
    for (const cp of cps) {
      const cls = cccOf(cp);
      if (lastClass > cls && cls !== 0) return "no";
      if (inPairs(t.quickCheckNo, cp)) return "no";
      if (inPairs(t.quickCheckMaybe, cp)) result = "maybe";
      lastClass = cls;
    }
    return result;
  };

  const decompose = (cps) => {
    const out = [];
    for (const cp of cps) {
      if (cp >= SBase && cp < SBase + SCount) {
        const s = cp - SBase;
        out.push(LBase + Math.floor(s / (VCount * TCount)), VBase + Math.floor((s % (VCount * TCount)) / TCount));
        if (s % TCount !== 0) out.push(TBase + (s % TCount));
        continue;
      }
      const index = exact(t.decompositionKeys, cp);
      if (index < 0) {
        out.push(cp);
        continue;
      }
      const entry = t.decompositionEntries[index];
      const offset = entry >>> 3;
      out.push(...t.decompositionPool.slice(offset, offset + (entry & 7)));
    }
    return out;
  };

  const reorder = (cps) => {
    const result = [];
    let run = [];
    const flush = () => {
      // Array.prototype.sort is stable, so equal classes keep their order.
      run.sort((a, b) => a[0] - b[0]);
      for (const [, cp] of run) result.push(cp);
      run = [];
    };
    for (const cp of cps) {
      const cls = cccOf(cp);
      if (cls === 0) {
        flush();
        result.push(cp);
      } else {
        run.push([cls, cp]);
      }
    }
    flush();
    return result;
  };

  const composePair = (first, second) => {
    if (first >= LBase && first < LBase + LCount && second >= VBase && second < VBase + VCount) {
      return SBase + ((first - LBase) * VCount + (second - VBase)) * TCount;
    }
    if (first >= SBase && first < SBase + SCount && (first - SBase) % TCount === 0 && second > TBase && second < TBase + TCount) {
      return first + (second - TBase);
    }
    const index = exact(t.compositionKeys, first * COMPOSITION_SHIFT + second);
    return index < 0 ? null : t.compositionValues[index];
  };

  const compose = (cps) => {
    if (cps.length === 0) return cps;
    const out = [cps[0]];
    let starterIndex = 0;
    let lastClass = cccOf(cps[0]);
    if (lastClass !== 0) lastClass = 256;
    for (let i = 1; i < cps.length; i++) {
      const cp = cps[i];
      const cls = cccOf(cp);
      const composite = composePair(out[starterIndex], cp);
      if (composite !== null && (lastClass < cls || lastClass === 0)) {
        out[starterIndex] = composite;
        continue;
      }
      if (cls === 0) starterIndex = out.length;
      lastClass = cls;
      out.push(cp);
    }
    return out;
  };

  const decomposeAndCompose = (cps) => compose(reorder(decompose(cps)));
  const normalize = (cps) => (quickCheck(cps) === "yes" ? cps : decomposeAndCompose(cps));
  return { normalize, decomposeAndCompose, quickCheck };
}

/** Every NormalizationTest NFC invariant, the Part 1 complement, and a cross-check with Node. */
function nfcSelfTest(packed, test) {
  const expectedCounts = [46, 17154, 2004, 194, 735, 38];
  const counts = expectedCounts.map((_, part) => test.lines.filter((l) => l.part === part).length);
  if (test.parts.length !== expectedCounts.length || !sameArray(counts, expectedCounts)) {
    fail(`NormalizationTest has parts ${test.parts.join(",")} with ${counts.join(",")} lines, expected ${expectedCounts.join(",")}`);
  }
  const nfc = packedNFC(packed);
  const where = (l) => `NormalizationTest.txt:${l.line}`;
  const UNASSIGNED_IN_NODE = /\p{Cn}/u;
  let nodeCompared = 0;
  for (const l of test.lines) {
    // c2 == NFC(c1) == NFC(c2) == NFC(c3), and c4 == NFC(c4) == NFC(c5), by column index.
    for (const [expected, inputs] of [[1, [0, 1, 2]], [3, [3, 4]]]) {
      for (const input of inputs) {
        if (!sameArray(nfc.normalize(l.columns[input]), l.columns[expected])) {
          fail(`${where(l)}: NFC(c${input + 1}) is not c${expected + 1}`);
        }
      }
    }
    for (const [k, column] of l.columns.entries()) {
      if (column.some(isSurrogate)) fail(`${where(l)}: a surrogate`);
      // The quick check may only say yes for NFC text, and no for text that isn't.
      const answer = nfc.quickCheck(column);
      const isNFC = sameArray(nfc.decomposeAndCompose(column), column);
      if ((answer === "yes" && !isNFC) || (answer === "no" && isNFC)) fail(`${where(l)} c${k + 1}: quick check ${answer}, NFC ${isNFC}`);
      const text = String.fromCodePoint(...column);
      if (!UNASSIGNED_IN_NODE.test(text)) {
        nodeCompared++;
        const node = Array.from(text.normalize("NFC"), (c) => c.codePointAt(0));
        if (!sameArray(node, nfc.normalize(column))) fail(`${where(l)} c${k + 1}: Node's NFC differs from the packed tables'`);
      }
    }
  }
  const part1 = new Set();
  for (const l of test.lines) {
    if (l.part !== 1) continue;
    if (l.columns[0].length !== 1) fail(`${where(l)}: a Part 1 line with ${l.columns[0].length} code points`);
    part1.add(l.columns[0][0]);
  }
  let outside = 0;
  for (let cp = 0; cp <= 0x10ffff; cp++) {
    if (isSurrogate(cp) || part1.has(cp)) continue;
    outside++;
    if (!sameArray(nfc.normalize([cp]), [cp]) || !sameArray(nfc.decomposeAndCompose([cp]), [cp])) {
      fail(`NFC(${U(cp)}) is not ${U(cp)}, and ${U(cp)} is outside Part 1`);
    }
  }
  return (
    `NormalizationTest ${UNICODE.version} ${test.lines.length}/${test.lines.length} lines; ` +
    `outside part 1: ${outside}/${outside} code points; Node ${process.version} agrees on ${nodeCompared} strings`
  );
}

// ── Main (last, so every module-level constant above is initialised) ───────────

await run(TAG, async () => {
  const options = parseArgs(process.argv.slice(2));
  const sources = new Sources(options);
  if (options.fetchOnly) {
    await sources.fetchAll();
    return;
  }
  const idna = idnaTables(sources);
  const nfc = await nfcTables(sources);
  writeOutput(TAG, "Sources/TR46/Generated/IDNATables.swift", idna.output, idna.summary);
  writeOutput(TAG, "Sources/TR46/Generated/NFCTables.swift", nfc.output, nfc.summary);
});
