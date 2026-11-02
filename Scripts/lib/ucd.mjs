/**
 * ucd.mjs
 *
 * Strict parsers for the Unicode 18.0.0 files the generators read. A line that doesn't have the
 * documented shape is an error, not something to skip.
 */
import { fail } from "./sources.mjs";

const HEX = /^[0-9A-F]{4,6}$/;

/** One code point in the UCD's upper-case hex form. */
export function parseCodePoint(text, where) {
  if (!HEX.test(text)) fail(`${where}: "${text}" is not a code point`);
  const value = parseInt(text, 16);
  if (value > 0x10ffff) fail(`${where}: ${text} is above 10FFFF`);
  return value;
}

/** "0041" or "0041..005A" → [lo, hi]. */
export function parseRange(text, where) {
  const parts = text.trim().split("..");
  if (parts.length > 2) fail(`${where}: "${text}" is not a range`);
  const lo = parseCodePoint(parts[0], where);
  const hi = parts.length === 2 ? parseCodePoint(parts[1], where) : lo;
  if (hi < lo) fail(`${where}: "${text}" runs backwards`);
  return [lo, hi];
}

/** Space-separated code points, as in UnicodeData's decomposition field and NormalizationTest. */
export function parseCodePoints(text, where) {
  const trimmed = text.trim();
  if (trimmed === "") fail(`${where}: no code points`);
  return trimmed.split(" ").map((part) => parseCodePoint(part, where));
}

/** Data lines with their 1-based line numbers, comments stripped, blank lines dropped. */
function dataLines(text) {
  const lines = [];
  for (const [index, raw] of text.split("\n").entries()) {
    const data = raw.replace(/#.*$/, "").trim();
    if (data !== "") lines.push({ line: index + 1, data, raw });
  }
  return lines;
}

/**
 * UnicodeData.txt → entries in code point order:
 *   { first, last, name, gc, ccc, decompositionTag, decomposition }
 * `<…, First>`/`<…, Last>` pairs become one entry with first < last. decompositionTag is null for a
 * canonical decomposition and the tag ("compat", "font", …) otherwise; decomposition is null when
 * there is none.
 */
export function parseUnicodeData(text) {
  const entries = [];
  let open = null;
  for (const [index, raw] of text.split("\n").entries()) {
    if (raw === "") continue;
    const where = `UnicodeData.txt:${index + 1}`;
    const fields = raw.split(";");
    if (fields.length !== 15) fail(`${where}: ${fields.length} fields, expected 15`);
    const cp = parseCodePoint(fields[0], where);
    const name = fields[1];
    const ccc = Number(fields[3]);
    if (!/^\d+$/.test(fields[3]) || ccc > 254) fail(`${where}: combining class "${fields[3]}"`);
    let decompositionTag = null;
    let decomposition = null;
    if (fields[5] !== "") {
      const match = /^(?:<(\w+)> )?([0-9A-F ]+)$/.exec(fields[5]);
      if (!match) fail(`${where}: decomposition "${fields[5]}"`);
      decompositionTag = match[1] ?? null;
      decomposition = parseCodePoints(match[2], where);
    }
    const entry = { first: cp, last: cp, name, gc: fields[2], ccc, decompositionTag, decomposition };
    if (name.endsWith(", First>")) {
      if (open) fail(`${where}: a range opens inside another`);
      open = entry;
      continue;
    }
    if (name.endsWith(", Last>")) {
      if (!open || open.name.replace(", First>", "") !== name.replace(", Last>", "")) fail(`${where}: an unopened range`);
      if (open.ccc !== ccc || open.decomposition || decomposition) fail(`${where}: a range with properties`);
      entries.push({ ...open, last: cp, name: open.name.replace(", First>", ">") });
      open = null;
      continue;
    }
    if (open) fail(`${where}: a range is still open`);
    entries.push(entry);
  }
  if (open) fail("UnicodeData.txt: the last range never closes");
  for (let i = 1; i < entries.length; i++) {
    if (entries[i].first <= entries[i - 1].last) fail(`UnicodeData.txt: ${entries[i].first.toString(16)} is out of order`);
  }
  return entries;
}

/** CompositionExclusions.txt → the code points it lists (commented-out lines are not listed). */
export function parseCompositionExclusions(text) {
  const result = [];
  for (const { line, data } of dataLines(text)) {
    const [lo, hi] = parseRange(data, `CompositionExclusions.txt:${line}`);
    for (let cp = lo; cp <= hi; cp++) result.push(cp);
  }
  return result;
}

/**
 * DerivedNormalizationProps.txt → Map from "Property" or "Property=Value" to [lo, hi] ranges in
 * file order. "0340..0341 ; NFC_QC; N" is filed under "NFC_QC=N". A binary property such as
 * Full_Composition_Exclusion has no value.
 */
export function parseDerivedNormalizationProps(text) {
  const result = new Map();
  for (const { line, data } of dataLines(text)) {
    const where = `DerivedNormalizationProps.txt:${line}`;
    const fields = data.split(";").map((field) => field.trim());
    if (fields.length < 2 || fields.length > 3) fail(`${where}: ${fields.length} fields`);
    if (!/^[A-Za-z_]+$/.test(fields[1])) fail(`${where}: property "${fields[1]}"`);
    // A value may be a code point sequence (FC_NFKC, NFKC_CF) or empty; only the name is checked.
    const key = fields.length === 3 ? `${fields[1]}=${fields[2]}` : fields[1];
    if (!result.has(key)) result.set(key, []);
    result.get(key).push(parseRange(fields[0], where));
  }
  return result;
}

/** DerivedAge.txt → [lo, hi, "major.minor"] in file order (grouped by age, not sorted). */
export function parseDerivedAge(text) {
  const result = [];
  for (const { line, data } of dataLines(text)) {
    const where = `DerivedAge.txt:${line}`;
    const fields = data.split(";").map((field) => field.trim());
    if (fields.length !== 2 || !/^\d+\.\d+$/.test(fields[1])) fail(`${where}: "${data}"`);
    const [lo, hi] = parseRange(fields[0], where);
    result.push([lo, hi, fields[1]]);
  }
  return result;
}

/** "15.1" → 15001, so ages compare as numbers. */
export const ageRank = (age) => {
  const [major, minor] = age.split(".").map(Number);
  return major * 1000 + minor;
};

/** A lookup from code point to its DerivedAge, or null for an unassigned one. */
export function ageLookup(ranges) {
  const sorted = [...ranges].sort((a, b) => a[0] - b[0]);
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i][0] <= sorted[i - 1][1]) fail(`DerivedAge.txt: overlapping ranges at ${sorted[i][0].toString(16)}`);
  }
  return (cp) => {
    let lo = 0;
    let hi = sorted.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (cp < sorted[mid][0]) hi = mid - 1;
      else if (cp > sorted[mid][1]) lo = mid + 1;
      else return sorted[mid][2];
    }
    return null;
  };
}

/**
 * NormalizationTest.txt → { parts: ["Part0", …], lines: [{ part, line, hex: [c1…c5], columns: [[cps]…] }] }.
 * `hex` keeps each column in the file's own form (upper-case, space separated).
 */
export function parseNormalizationTest(text) {
  const parts = [];
  const lines = [];
  let part = null;
  for (const [index, raw] of text.split("\n").entries()) {
    const where = `NormalizationTest.txt:${index + 1}`;
    const data = raw.replace(/#.*$/, "").trim();
    if (data === "") continue;
    const header = /^@Part(\d+)$/.exec(data);
    if (header) {
      part = Number(header[1]);
      if (part !== parts.length) fail(`${where}: @Part${part} out of order`);
      parts.push(`Part${part}`);
      continue;
    }
    if (part === null) fail(`${where}: a test line before any @Part`);
    const fields = data.split(";");
    if (fields.length !== 6 || fields[5].trim() !== "") fail(`${where}: ${fields.length} fields, expected 5 and a trailing ";"`);
    const hex = fields.slice(0, 5).map((field) => field.trim());
    const columns = hex.map((column) => parseCodePoints(column, where));
    lines.push({ part, line: index + 1, hex, columns });
  }
  return { parts, lines };
}

/**
 * IdnaTestV2's escapes, as tr46's test/unicode.js reads them: \uXXXX is one UTF-16 unit (so a
 * pair is written as two escapes, and one alone is a lone surrogate). \x{…} is a code point; the
 * file uses it only in its header comments, and parseIdnaTestV2 asserts that.
 */
export function unescapeIdna(field) {
  return field
    .replace(/\\u([0-9A-Fa-f]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\x\{([0-9A-Fa-f]+)\}/g, (_, h) => String.fromCodePoint(parseInt(h, 16)));
}

/**
 * IdnaTestV2.txt → rows of { line, source, toUnicode, toUnicodeStatus, toAsciiN, toAsciiNStatus,
 * toAsciiT, toAsciiTStatus }, split at "#" and then ";" as tr46's harness does. Each field is the
 * trimmed, unescaped text, with `""` read as the empty string and a blank field as null, so the
 * file's inheritance rules can be applied by the caller.
 */
export function parseIdnaTestV2(text) {
  const names = ["source", "toUnicode", "toUnicodeStatus", "toAsciiN", "toAsciiNStatus", "toAsciiT", "toAsciiTStatus"];
  const rows = [];
  for (const [index, raw] of text.split("\n").entries()) {
    const data = raw.replace(/#.*$/, "");
    if (data.trim() === "") continue;
    const where = `IdnaTestV2.txt:${index + 1}`;
    if (/\\x\{/.test(data)) fail(`${where}: a \\x{…} escape in a data line; tr46's harness reads only \\uXXXX`);
    const fields = data.split(";").map((field) => field.trim());
    if (fields.length !== names.length) fail(`${where}: ${fields.length} fields, expected ${names.length}`);
    const row = { line: index + 1 };
    names.forEach((name, i) => {
      const field = fields[i];
      row[name] = field === "" ? null : field === '""' ? "" : unescapeIdna(field);
    });
    rows.push(row);
  }
  return rows;
}

/** "[B1, V6]" → ["B1", "V6"]; "[]" → []. */
export function parseIdnaStatus(field, where) {
  const match = /^\[([A-Z0-9_, ]*)\]$/.exec(field);
  if (!match) fail(`${where}: status "${field}"`);
  return match[1].trim() === "" ? [] : match[1].split(",").map((code) => code.trim());
}
