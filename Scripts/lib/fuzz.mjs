/**
 * fuzz.mjs
 *
 * The seeded PRNG for generated fuzz inputs. The same seed gives the same sequence on every run,
 * so a fuzz-derived vector file is reproducible byte for byte.
 */

/** "tr46" in ASCII. */
export const FUZZ_SEED = 0x74723436;

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
