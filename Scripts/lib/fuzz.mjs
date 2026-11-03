/**
 * fuzz.mjs
 *
 * The seeded PRNG and the generator of fuzz inputs for differential.json. The
 * same seed gives the same sequence on every run, so the file is reproducible byte for byte.
 *
 * An input is 1–4 labels (weighted 40/30/20/10) joined by "." 85% of the time, otherwise by one of
 * the other full stops tr46 maps to "." (U+3002, U+FF0E, U+FF61). A label is one of:
 *
 *   60%  0–12 code points drawn from the pools below
 *   15%  "xn--" and 0–12 characters from [a-z0-9-], which decode to whatever they decode to
 *   15%  "xn--" and punycode.encode of a pool label; a quarter of these have a raw surrogate value
 *        spliced in with String.fromCharCode first, so the label decodes to a lone surrogate (J1's
 *        "others stay alone", and J3)
 *   10%  a hyphen shape around a short pool label: "-x", "x-" or "ab--x"
 *
 * punycode.encode reads its argument with ucs2decode, which pairs a high surrogate with a low one
 * that follows it, so no encoded label here decodes to two surrogate values that re-pair. That
 * half of J1 is covered by the curated inputs instead.
 *
 * Every pool comes from tr46's own mapping table and regex classes or from the Unicode 18.0.0
 * UCD, and holds no surrogate and nothing that is newer than Node (assigned in Unicode 18.0.0 but
 * \p{Cn} under Node's Unicode 16.0), so no fuzz input is lost to the newer-than-Node exclusion
 * in generate-vectors.mjs through a pool.
 */
import { fail } from "./sources.mjs";

/** "tr46" in ASCII. */
export const FUZZ_SEED = 0x74723436;

/** How many fuzz inputs differential.json holds. */
export const FUZZ_COUNT = 3000;

/** mulberry32: a 32-bit state, returning floats in [0, 1). */
export function mulberry32(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Helpers over one mulberry32 stream. */
export function createRandom(seed = FUZZ_SEED) {
  const next = mulberry32(seed);
  return {
    next,
    /** An integer in [lo, hi], inclusive. */
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    /** One element of a non-empty array. */
    pick: (items) => items[Math.floor(next() * items.length)],
    /** An index chosen with the given relative weights. */
    weighted: (weights) => {
      const total = weights.reduce((sum, w) => sum + w, 0);
      let roll = next() * total;
      for (let i = 0; i < weights.length; i++) {
        roll -= weights[i];
        if (roll < 0) return i;
      }
      return weights.length - 1;
    },
  };
}

// ── Pools ──────────────────────────────────────────────────────────────────────

const isSurrogate = (cp) => cp >= 0xd800 && cp <= 0xdfff;

/** Every code point in inclusive [lo, hi] ranges, in order. */
function expand(ranges) {
  const result = [];
  for (const [lo, hi] of ranges) for (let cp = lo; cp <= hi; cp++) result.push(cp);
  return result;
}

/**
 * The pools a pool label draws from, each with its share of the label's code points. A pool with
 * several parts draws a part uniformly first, so a small part (U+1E9E, the Hangul jamo) isn't
 * drowned by a large one.
 *
 *   rows, status    tr46's mapping table and STATUS_MAPPING (tr46-data.mjs)
 *   classes         tr46's regex classes by Swift name (tr46-data.mjs readClasses)
 *   unicodeData     UnicodeData.txt 18.0.0 entries (ucd.mjs parseUnicodeData)
 *   newerThanNode   (cp) => whether cp is assigned in Unicode 18.0.0 but \p{Cn} under Node
 */
export function createPools({ rows, status, classes, unicodeData, newerThanNode }) {
  const byStatus = (wanted) => rows.filter((row) => row.status === wanted).map((row) => [row.lo, row.hi]);
  const ranges = (name) => {
    const table = classes.find((c) => c.swiftName === name);
    if (!table) fail(`fuzz: no tr46 class ${name}`);
    return table.ranges;
  };
  const decomposable = [];
  const composable = new Set();
  for (const entry of unicodeData) {
    if (entry.decomposition === null || entry.decompositionTag !== null) continue;
    for (let cp = entry.first; cp <= entry.last; cp++) decomposable.push(cp);
    if (entry.decomposition.length === 2) entry.decomposition.forEach((cp) => composable.add(cp));
  }
  const asciiCore = [..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].map((ch) => ch.codePointAt(0));
  const asciiOther = expand([[0x00, 0x7f]]).filter((cp) => !asciiCore.includes(cp));

  const pools = [
    ["ASCII letters, digits and -", 30, [asciiCore]],
    ["other ASCII", 10, [asciiOther]],
    ["mapped", 10, [expand(byStatus(status.mapped))]],
    ["deviation, plus U+1E9E", 5, [expand(byStatus(status.deviation)), [0x1e9e]]],
    ["ignored", 3, [expand(byStatus(status.ignored))]],
    ["disallowed", 5, [expand(byStatus(status.disallowed))]],
    ["bidi R and AL", 8, [expand(ranges("bidiS1RTL"))]],
    ["EN and AN digits", 5, [expand(ranges("bidiS4EN")), expand(ranges("bidiS4AN"))]],
    ["combining marks", 8, [expand(ranges("combiningMarks"))]],
    ["virama", 3, [expand(ranges("combiningClassVirama"))]],
    [
      "joining types L, D, R and T",
      5,
      [expand(ranges("validZWNJBefore")), expand(ranges("validZWNJAfter")), expand(ranges("validZWNJTransparentBefore"))],
    ],
    [
      "NFC: decomposable, composable, Hangul jamo",
      8,
      [decomposable, [...composable].sort((a, b) => a - b), expand([[0x1100, 0x11ff]])],
    ],
  ].map(([name, share, parts]) => {
    const filtered = parts.map((part) => part.filter((cp) => !isSurrogate(cp) && !newerThanNode(cp)));
    filtered.forEach((part, i) => {
      if (part.length === 0) fail(`fuzz: pool "${name}" part ${i} is empty`);
    });
    return { name, share, parts: filtered };
  });
  const total = pools.reduce((sum, pool) => sum + pool.share, 0);
  if (total !== 100) fail(`fuzz: the pool shares add up to ${total}, not 100`);
  return pools;
}

// ── Inputs ─────────────────────────────────────────────────────────────────────

const LABEL_COUNT_WEIGHTS = [40, 30, 20, 10];
const SEPARATORS = [".", "\u3002", "\uFF0E", "\uFF61"];
const SEPARATOR_WEIGHTS = [85, 5, 5, 5];
const LABEL_KIND_WEIGHTS = [60, 15, 15, 10];
const PUNYCODE_DIGITS = [..."abcdefghijklmnopqrstuvwxyz0123456789-"];
const HYPHEN_SHAPES = [(x) => `-${x}`, (x) => `${x}-`, (x) => `ab--${x}`];

/**
 * A function that returns the next fuzz input each time it is called.
 *   random     createRandom(FUZZ_SEED)
 *   pools      createPools(...)
 *   punycode   punycode.js 2.3.1, the copy tr46 itself loads
 */
export function createFuzzer({ random, pools, punycode }) {
  const weights = pools.map((pool) => pool.share);
  const codePoint = () => random.pick(random.pick(pools[random.weighted(weights)].parts));
  const poolLabel = (min, max) => {
    const count = random.int(min, max);
    const codePoints = [];
    for (let i = 0; i < count; i++) codePoints.push(codePoint());
    return codePoints;
  };
  const label = () => {
    switch (random.weighted(LABEL_KIND_WEIGHTS)) {
      case 0:
        return String.fromCodePoint(...poolLabel(0, 12));
      case 1: {
        let digits = "";
        for (let i = random.int(0, 12); i > 0; i--) digits += random.pick(PUNYCODE_DIGITS);
        return `xn--${digits}`;
      }
      case 2: {
        const parts = poolLabel(0, 12).map((cp) => String.fromCodePoint(cp));
        if (random.next() < 0.25) parts.splice(random.int(0, parts.length), 0, String.fromCharCode(random.int(0xd800, 0xdfff)));
        return `xn--${punycode.encode(parts.join(""))}`;
      }
      default:
        return random.pick(HYPHEN_SHAPES)(String.fromCodePoint(...poolLabel(1, 6)));
    }
  };
  return () => {
    let input = label();
    for (let i = random.weighted(LABEL_COUNT_WEIGHTS); i > 0; i--) {
      input += SEPARATORS[random.weighted(SEPARATOR_WEIGHTS)] + label();
    }
    return input;
  };
}
