/**
 * tr46-data.mjs
 *
 * Reads tr46 7.0.0's data out of the verified tarball (sources.mjs): lib/statusMapping.js,
 * lib/mappingTable.json and lib/regexes.js. It refuses anything it doesn't expect, because a table
 * that quietly differs from tr46 is the failure this package exists to prevent.
 *
 *   - statusMapping.js: exactly {mapped:1, valid:2, disallowed:3, deviation:6, ignored:7}.
 *   - mappingTable.json: contiguous rows over 0…10FFFF, known statuses, a mapping on every mapped
 *     and deviation row, no surrogate in any mapping.
 *   - regexes.js: the 12 regexes, in order, each a fixed skeleton around bracket classes with no
 *     negated class. Each class is evaluated over every code point, surrogates included, which is
 *     how a /u regex sees a lone surrogate (by its raw value). Every single-class regex is
 *     cross-checked against the live module.
 */
import { fail } from "./sources.mjs";

export const EXPECTED_STATUS = { mapped: 1, valid: 2, disallowed: 3, deviation: 6, ignored: 7 };

/** statusMapping.js's STATUS_MAPPING, after checking it is exactly EXPECTED_STATUS. */
export function readStatusMapping(tr46) {
  const { STATUS_MAPPING } = tr46.require("./lib/statusMapping.js");
  if (JSON.stringify(STATUS_MAPPING) !== JSON.stringify(EXPECTED_STATUS)) {
    fail(`statusMapping.js is ${JSON.stringify(STATUS_MAPPING)}, expected ${JSON.stringify(EXPECTED_STATUS)}`);
  }
  return STATUS_MAPPING;
}

/** A JS string's code points, pairing surrogates; a lone surrogate is refused. */
function scalarsOf(text, where) {
  const scalars = [];
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        scalars.push((unit - 0xd800) * 0x400 + (low - 0xdc00) + 0x10000);
        i++;
        continue;
      }
    }
    if (unit >= 0xd800 && unit <= 0xdfff) fail(`${where}: a lone surrogate in a mapping`);
    scalars.push(unit);
  }
  return scalars;
}

/**
 * mappingTable.json → rows { lo, hi, status, mapping, scalars }, contiguous over 0…10FFFF.
 * `mapping` is tr46's string (undefined when the row has none) and `scalars` its code points.
 * Deviation rows keep their mapping: transitional processing reads it.
 */
export function readMappingTable(tr46, status) {
  const table = JSON.parse(tr46.read("lib/mappingTable.json").toString("utf8"));
  const statuses = new Set(Object.values(status));
  const rows = table.map((row, index) => {
    const where = `mappingTable.json row ${index}`;
    if (!Array.isArray(row) || row.length < 2 || row.length > 3) fail(`${where}: ${JSON.stringify(row)}`);
    const [range, rowStatus, mapping] = row;
    const [lo, hi] = Array.isArray(range) ? range : [range, range];
    if (!Number.isInteger(lo) || !Number.isInteger(hi)) fail(`${where}: range ${JSON.stringify(range)}`);
    if (!statuses.has(rowStatus)) fail(`${where}: unknown status ${rowStatus}`);
    if (rowStatus === status.mapped && typeof mapping !== "string") fail(`${where}: a mapped row with no mapping`);
    if (rowStatus === status.deviation && typeof mapping !== "string") fail(`${where}: a deviation row with no mapping`);
    if (mapping !== undefined && typeof mapping !== "string") fail(`${where}: mapping ${JSON.stringify(mapping)}`);
    if (mapping !== undefined && rowStatus !== status.mapped && rowStatus !== status.deviation) {
      fail(`${where}: status ${rowStatus} with a mapping`);
    }
    return { lo, hi, status: rowStatus, mapping, scalars: mapping === undefined ? [] : scalarsOf(mapping, where) };
  });
  let expectedLo = 0;
  for (const [index, row] of rows.entries()) {
    if (row.lo !== expectedLo || row.hi < row.lo) fail(`mappingTable.json row ${index}: not contiguous at ${row.lo.toString(16)}`);
    expectedLo = row.hi + 1;
  }
  if (expectedLo !== 0x110000) fail(`mappingTable.json ends at ${(expectedLo - 1).toString(16)}, not 10FFFF`);
  return rows;
}

/** The row holding `cp`, by binary search for the last row starting at or below it. */
export function rowAt(rows, cp) {
  let lo = 0;
  let hi = rows.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (rows[mid].lo <= cp) lo = mid;
    else hi = mid - 1;
  }
  return rows[lo];
}

/** Adjacent rows merge only when status and mapping are equal, so every code point keeps its pair. */
export function mergeRuns(rows) {
  const runs = [];
  for (const row of rows) {
    const last = runs[runs.length - 1];
    if (last && last.status === row.status && last.scalars.join(",") === row.scalars.join(",")) continue;
    runs.push({ start: row.lo, status: row.status, scalars: row.scalars });
  }
  return runs;
}

// ── regexes.js ─────────────────────────────────────────────────────────────────

/** [regex, skeleton, the Swift name of each bracket class in it]. */
export const REGEXES = [
  ["combiningMarks", "[#0]", ["combiningMarks"]],
  ["combiningClassVirama", "[#0]", ["combiningClassVirama"]],
  ["validZWNJ", "[#0][#1]*\\u200C[#2]*[#3]",
    ["validZWNJBefore", "validZWNJTransparentBefore", "validZWNJTransparentAfter", "validZWNJAfter"]],
  ["bidiDomain", "[#0]", ["bidiDomain"]],
  ["bidiS1LTR", "[#0]", ["bidiS1LTR"]],
  ["bidiS1RTL", "[#0]", ["bidiS1RTL"]],
  ["bidiS2", "^[#0]*$", ["bidiS2"]],
  ["bidiS3", "[#0][#1]*$", ["bidiS3Last", "bidiS3Trailing"]],
  ["bidiS4EN", "[#0]", ["bidiS4EN"]],
  ["bidiS4AN", "[#0]", ["bidiS4AN"]],
  ["bidiS5", "^[#0]*$", ["bidiS5"]],
  ["bidiS6", "[#0][#1]*$", ["bidiS6Last", "bidiS6Trailing"]],
];

/** One line of documentation per Swift class table. */
export const CLASS_DOCS = {
  combiningMarks: "combiningMarks: General_Category=Mark. A label must not begin with one.",
  combiningClassVirama: "combiningClassVirama: Canonical_Combining_Class=Virama. A joiner after one is allowed.",
  validZWNJBefore: "validZWNJ #0: Joining_Type L or D, left of a ZWNJ.",
  validZWNJTransparentBefore: "validZWNJ #1: Joining_Type T, between the left letter and the ZWNJ.",
  validZWNJTransparentAfter: "validZWNJ #2: Joining_Type T, between the ZWNJ and the right letter.",
  validZWNJAfter: "validZWNJ #3: Joining_Type R or D, right of a ZWNJ.",
  bidiDomain: "bidiDomain: Bidi_Class R, AL or AN. Any one of them makes the domain a Bidi domain name.",
  bidiS1LTR: "bidiS1LTR: RFC 5893 rule 1, a first code point that makes the label LTR.",
  bidiS1RTL: "bidiS1RTL: RFC 5893 rule 1, a first code point that makes the label RTL.",
  bidiS2: "bidiS2: RFC 5893 rule 2, every code point of an RTL label.",
  bidiS3Last: "bidiS3 #0: RFC 5893 rule 3, the last non-NSM code point of an RTL label.",
  bidiS3Trailing: "bidiS3 #1: RFC 5893 rule 3, what may follow it (NSM).",
  bidiS4EN: "bidiS4EN: RFC 5893 rule 4, European numbers. An RTL label can't mix them with bidiS4AN.",
  bidiS4AN: "bidiS4AN: RFC 5893 rule 4, Arabic numbers.",
  bidiS5: "bidiS5: RFC 5893 rule 5, every code point of an LTR label.",
  bidiS6Last: "bidiS6 #0: RFC 5893 rule 6, the last non-NSM code point of an LTR label.",
  bidiS6Trailing: "bidiS6 #1: RFC 5893 rule 6, what may follow it (NSM).",
};

/** Splits a regex body into its skeleton and its bracket classes, honouring escapes. */
function decompose(body) {
  let skeleton = "";
  const classes = [];
  let i = 0;
  while (i < body.length) {
    const c = body[i];
    if (c === "\\") {
      skeleton += body.slice(i, i + 2);
      i += 2;
    } else if (c === "[") {
      let j = i + 1;
      if (body[j] === "^") fail("regexes.js: a negated class");
      while (j < body.length && body[j] !== "]") {
        if (body[j] === "\\") j++;
        j++;
      }
      if (j >= body.length) fail("regexes.js: an unterminated class");
      classes.push(body.slice(i, j + 1));
      skeleton += `[#${classes.length - 1}]`;
      i = j + 1;
    } else {
      skeleton += c;
      i++;
    }
  }
  return { skeleton, classes };
}

/** Inclusive [lo, hi] ranges of the code points a class matches, surrogates included. */
export function evaluateClass(cls) {
  const re = new RegExp(`^${cls}$`, "u");
  const ranges = [];
  let open = -1;
  for (let cp = 0; cp <= 0x110000; cp++) {
    const hit = cp <= 0x10ffff && re.test(String.fromCodePoint(cp));
    if (hit && open < 0) open = cp;
    if (!hit && open >= 0) {
      ranges.push([open, cp - 1]);
      open = -1;
    }
  }
  return ranges;
}

/** Membership in sorted inclusive ranges. */
export function inRanges(ranges, cp) {
  let lo = 0;
  let hi = ranges.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (cp < ranges[mid][0]) hi = mid - 1;
    else if (cp > ranges[mid][1]) lo = mid + 1;
    else return true;
  }
  return false;
}

/**
 * regexes.js → [{ swiftName, regex, index, ranges }], one per bracket class, in REGEXES order,
 * after checking the declarations, the exports, every skeleton, and every single-class regex
 * against the live module over all of 0…10FFFF.
 */
export function readClasses(tr46) {
  const source = tr46.read("lib/regexes.js").toString("utf8");
  const declarations = [...source.matchAll(/^const (\w+) = \/(.*)\/u;$/gm)].map((m) => [m[1], m[2]]);
  if (declarations.length !== REGEXES.length) {
    fail(`regexes.js has ${declarations.length} declarations, expected ${REGEXES.length}`);
  }
  const live = tr46.require("./lib/regexes.js");
  if (JSON.stringify(Object.keys(live)) !== JSON.stringify(REGEXES.map(([name]) => name))) {
    fail(`regexes.js exports ${Object.keys(live).join(", ")}`);
  }
  const tables = [];
  for (const [index, [name, skeleton, swiftNames]] of REGEXES.entries()) {
    const [declared, body] = declarations[index];
    if (declared !== name) fail(`regex ${index} is ${declared}, expected ${name}`);
    if (live[name].flags !== "u") fail(`${name} has flags "${live[name].flags}", expected "u"`);
    const parts = decompose(body);
    if (parts.skeleton !== skeleton) fail(`${name}'s skeleton is ${parts.skeleton}, expected ${skeleton}`);
    if (parts.classes.length !== swiftNames.length) fail(`${name} has ${parts.classes.length} classes`);
    const evaluated = parts.classes.map(evaluateClass);
    if (evaluated.length === 1) {
      // `[X]` and `^[X]*$` both match a one-code-point string exactly when it is in X.
      for (let cp = 0; cp <= 0x10ffff; cp++) {
        if (live[name].test(String.fromCodePoint(cp)) !== inRanges(evaluated[0], cp)) {
          fail(`${name} disagrees with the live regex at U+${cp.toString(16).toUpperCase()}`);
        }
      }
    }
    evaluated.forEach((ranges, k) => tables.push({ swiftName: swiftNames[k], regex: name, index: k, ranges }));
  }
  return tables;
}
