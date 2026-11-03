/**
 * sources.mjs
 *
 * Every upstream input the generators read, pinned by hash, and the code that obtains and verifies
 * them. Nothing is trusted because of where it came from: a file is hashed every time it is used,
 * whether it was just downloaded, read from the cache or passed on the command line.
 *
 *   tr46 7.0.0, punycode 2.3.1   `npm pack`, sha512 of the .tgz, then SHA-256 of each member used
 *   Unicode 18.0.0               https://www.unicode.org/Public/18.0.0/, SHA-256 and size
 *   web-platform-tests           raw.githubusercontent.com at a fixed commit, SHA-256 and size
 *
 * Downloads are cached in .build/tr46-sources (gitignored) unless --data-dir names another
 * directory. A cached file that fails its hash is an error, never a reason to download it again
 * quietly: delete it to fetch a fresh copy.
 *
 * Generator options, all optional:
 *   --tr46-tarball <path>       use this tr46-7.0.0.tgz instead of running npm pack
 *   --punycode-tarball <path>   use this punycode-2.3.1.tgz instead of running npm pack
 *   --unicode-dir <dir>         read the Unicode files from <dir>, as <dir>/ucd/UnicodeData.txt or
 *                               <dir>/UnicodeData.txt, instead of downloading them
 *   --data-dir <dir>            the download cache, instead of .build/tr46-sources
 *   --fetch-only                obtain and verify every pinned source, then exit
 *
 * Fetch and verify everything without generating anything:
 *   node -e 'import("./Scripts/lib/sources.mjs").then((m) => m.fetchAll())'
 */
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

// ── Pins ───────────────────────────────────────────────────────────────────────

/** The generators run on exactly this Node, so their output is byte-reproducible. Keep it equal to .node-version. */
export const NODE = { version: "v24.12.0", unicode: "16.0", icu: "77.1" };

export const TR46 = {
  name: "tr46",
  version: "7.0.0",
  unicodeVersion: "18.0.0",
  // = `npm view tr46@7.0.0 dist.integrity`
  integrity: "sha512-BcDSDW+SIGWVOns1Zm6Yg91q9AEj7eaID0QDY9oIqJD1A8dscNwMcl9Sms2DeuWCNov1X0/oXanHGYQBSLwZsg==",
  members: {
    "index.js": "dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646",
    "lib/mappingTable.json": "82ae922b231ebc91e7f9f7d761dd62a68d49698878a55f79e43e83cd435dc448",
    "lib/regexes.js": "eb690752aa1b1ac024251681317369bf96df463f3632d650163e0b8b658e4e1d",
    "lib/statusMapping.js": "ab7f706a1e3e74f4efd276560bb50e15f71dd0b20f85e87e21d1c18259420064",
    "LICENSE.md": "499d6d466d064e0460427967a344e2a32fcb86ea8c6cd1a285ec4f1fa03fba67",
  },
};

export const PUNYCODE = {
  name: "punycode",
  version: "2.3.1",
  // = `npm view punycode@2.3.1 dist.integrity`
  integrity: "sha512-vYt7UD1U9Wg6138shLtLOvdAu+8DsC/ilFtEVHcH+wydcSpNE20AfSOduf6MkRFahL5FY7X1oU7nKVZFtfq8Fg==",
  members: {
    "punycode.js": "6052a80eac47e46bd4de17ae0095e0192c336d3d7c387d292ad2176ebfc53d04",
    "LICENSE-MIT.txt": "483acb265f182907d1caf6cff9c16c96f31325ed23792832cc5d8b12d5f88c8a",
  },
};

export const UNICODE = {
  version: "18.0.0",
  baseURL: "https://www.unicode.org/Public/18.0.0/",
  files: {
    UnicodeData: {
      path: "ucd/UnicodeData.txt",
      bytes: 2243593,
      sha256: "0736451de439ae7baf1425136617da495e09ee5afbe6e394374db7009ea08950",
    },
    CompositionExclusions: {
      path: "ucd/CompositionExclusions.txt",
      bytes: 9007,
      sha256: "c759b100e9ae8960ae6b50fc5765950a7581fd9f30d4ef95f68f25a6d97e818e",
    },
    DerivedNormalizationProps: {
      path: "ucd/DerivedNormalizationProps.txt",
      bytes: 1396877,
      sha256: "98ac7f67d985fe781e317f6182e885e94cabb0c314769e6dd73e48b226931ccd",
    },
    NormalizationTest: {
      path: "ucd/NormalizationTest.txt",
      bytes: 2863708,
      sha256: "25a50d816764b04abfb4a646d3eb2b2a803284c3873d9a06757b94fe4513dde3",
    },
    DerivedAge: {
      path: "ucd/DerivedAge.txt",
      bytes: 142568,
      sha256: "58b04334e3a31f9612694bbc3f6bff4a302b7d424565bca9c47e30aa74f8dbac",
    },
    IdnaTestV2: {
      path: "idna/IdnaTestV2.txt",
      bytes: 776565,
      sha256: "0236b75c5b20dfd857b3b5cf75509887959d6ab00d6c7bda9b7dc3df518c1fde",
    },
  },
};

/**
 * The wptSHA in tr46 v7.0.0's scripts/getLatestTests.mjs (tag commit 6d09104f…), whose commit
 * message is "Update IDNA Test JSON to Unicode 18.0.0".
 */
export const WPT = {
  commit: "13748c36fdf9dd77cd0b34dd6b244256b365ea60",
  tr46Tag: "v7.0.0",
  tr46TagCommit: "6d09104f21991d496aa2a8535d21bdea91a9c216",
  baseURL: "https://raw.githubusercontent.com/web-platform-tests/wpt/13748c36fdf9dd77cd0b34dd6b244256b365ea60/",
  files: {
    toascii: {
      path: "url/resources/toascii.json",
      bytes: 9101,
      sha256: "644eba9d5b593df8095cfa307222f3014542ff9cc02d555f8e5660059d80470f",
    },
    idnaTestV2: {
      path: "url/resources/IdnaTestV2.json",
      bytes: 314263,
      sha256: "84de621e5239676e59e5a3e68ef3e2b1acde9da5480a633d2ef446ef03238b76",
    },
    // BSD-3-Clause, copied verbatim to Tests/TR46Tests/Resources/LICENSE-web-platform-tests.md.
    license: {
      path: "LICENSE.md",
      bytes: 1500,
      sha256: "5fac07febb0e2a97fb0d7b0def149ec08b642e1ba4b9c345283ab1cbd2af6570",
    },
  },
};

/**
 * GeoSpoof's parity fixture, copied once and byte-identical to
 * Tests/TR46Tests/Resources/geospoof-idna-vectors.json. It was produced by the GeoSpoof extension's
 * hostToASCII (tr46 7.0.0 under Node). The vectors generator asserts the hash and both counts.
 */
export const SEED_FIXTURE = {
  origin: "GeoSpoof iOS app repository, tests/fixtures/idna-vectors.json",
  commit: "5e655ee5be0a309f3c28515ecfe6587fb96cd17c",
  sha256: "7a41c3e0facc4f31dcbc12bc3093f539a0341e5fafd62954cdd619e4c283368a",
  counts: { curated: 59, idnaTestV2: 3710 },
};

// ── Failure ────────────────────────────────────────────────────────────────────

/** A failed assertion or a bad source. `run` prints its message alone, without a stack. */
export class GeneratorError extends Error {}

export function fail(message) {
  throw new GeneratorError(message);
}

/** Refuses any Node but `NODE`: another could normalize, iterate or format differently. */
export function checkNode() {
  const actual = { version: process.version, unicode: process.versions.unicode, icu: process.versions.icu };
  if (actual.version !== NODE.version || actual.unicode !== NODE.unicode || actual.icu !== NODE.icu) {
    fail(
      `Node ${NODE.version} (Unicode ${NODE.unicode}, ICU ${NODE.icu}) is required, ` +
        `this is ${actual.version} (Unicode ${actual.unicode}, ICU ${actual.icu}); see .node-version`
    );
  }
}

/** Runs a generator's main: checks Node, then exits 1 with "[tag] message" on any failure. */
export async function run(tag, main) {
  try {
    checkNode();
    await main();
  } catch (error) {
    const message = error instanceof GeneratorError ? error.message : error?.stack ?? String(error);
    console.error(`[${tag}] ${message}`);
    process.exit(1);
  }
}

// ── Arguments ──────────────────────────────────────────────────────────────────

const VALUE_OPTIONS = {
  "--tr46-tarball": "tr46Tarball",
  "--punycode-tarball": "punycodeTarball",
  "--unicode-dir": "unicodeDir",
  "--data-dir": "dataDir",
};

/** Parses the shared options. Paths are resolved against the working directory. */
export function parseArgs(argv) {
  const options = { fetchOnly: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--fetch-only") {
      options.fetchOnly = true;
      continue;
    }
    const [flag, inline] = arg.includes("=") ? [arg.slice(0, arg.indexOf("=")), arg.slice(arg.indexOf("=") + 1)] : [arg];
    const key = VALUE_OPTIONS[flag];
    if (!key) fail(`unknown option ${arg}; expected ${[...Object.keys(VALUE_OPTIONS), "--fetch-only"].join(", ")}`);
    const value = inline ?? argv[++i];
    if (value === undefined || value === "") fail(`${flag} needs a path`);
    options[key] = path.resolve(value);
  }
  return options;
}

// ── Hashing and downloading ────────────────────────────────────────────────────

export const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sha512Integrity = (bytes) => `sha512-${createHash("sha512").update(bytes).digest("base64")}`;

function verifyFile(bytes, pin, where) {
  const actual = sha256(bytes);
  if (actual !== pin.sha256) {
    fail(`checksum mismatch for ${where}: SHA-256 ${actual}, expected ${pin.sha256}. Delete the file to fetch it again.`);
  }
  if (pin.bytes !== undefined && bytes.length !== pin.bytes) {
    fail(`size mismatch for ${where}: ${bytes.length} bytes, expected ${pin.bytes}`);
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** GET with four attempts and backoff. A response that arrives but fails its hash is not retried. */
async function download(url, pin) {
  const attempts = 4;
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(120_000), redirect: "follow" });
      if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`);
      const bytes = Buffer.from(await response.arrayBuffer());
      verifyFile(bytes, pin, url);
      return bytes;
    } catch (error) {
      if (error instanceof GeneratorError) throw error;
      if (attempt === attempts) fail(`could not download ${url} after ${attempts} attempts: ${error.message}`);
      console.error(`[sources] ${url}: ${error.message}; retrying (${attempt}/${attempts - 1})`);
      await sleep(1000 * 2 ** (attempt - 1));
    }
  }
}

/** Writes through a temporary name, so an interrupted run never leaves a partial cache file. */
function writeAtomically(file, bytes) {
  mkdirSync(path.dirname(file), { recursive: true });
  const partial = `${file}.partial-${process.pid}`;
  writeFileSync(partial, bytes);
  renameSync(partial, file);
}

// ── Sources ────────────────────────────────────────────────────────────────────

/**
 * One generator run's view of the pinned sources. Every getter verifies what it returns, and
 * returns the bytes it verified, so nothing is read twice.
 */
export class Sources {
  constructor(options = {}) {
    this.options = options;
    this.dataDir = options.dataDir ?? path.join(ROOT, ".build", "tr46-sources");
    this.cache = new Map();
    this.extracted = null;
  }

  /** A Unicode 18.0.0 file, by its key in UNICODE.files: { url, path, sha256, bytes, text }. */
  async unicode(key) {
    const pin = UNICODE.files[key];
    if (!pin) fail(`no pinned Unicode file ${key}`);
    const url = UNICODE.baseURL + pin.path;
    let override;
    if (this.options.unicodeDir) {
      const candidates = [path.join(this.options.unicodeDir, pin.path), path.join(this.options.unicodeDir, path.basename(pin.path))];
      override = candidates.find((candidate) => existsSync(candidate));
      if (!override) fail(`--unicode-dir has no ${pin.path}; looked for ${candidates.join(" and ")}`);
    }
    return this.#file(`unicode:${key}`, pin, url, override, path.join(this.dataDir, `unicode-${UNICODE.version}`, pin.path));
  }

  /** A web-platform-tests file at WPT.commit, by its key in WPT.files. */
  async wpt(key) {
    const pin = WPT.files[key];
    if (!pin) fail(`no pinned WPT file ${key}`);
    const url = WPT.baseURL + pin.path;
    return this.#file(`wpt:${key}`, pin, url, undefined, path.join(this.dataDir, `wpt-${WPT.commit}`, pin.path));
  }

  async #file(cacheKey, pin, url, override, cached) {
    if (this.cache.has(cacheKey)) return this.cache.get(cacheKey);
    let bytes;
    if (override) {
      bytes = readFileSync(override);
      verifyFile(bytes, pin, override);
    } else if (existsSync(cached)) {
      bytes = readFileSync(cached);
      verifyFile(bytes, pin, cached);
    } else {
      bytes = await download(url, pin);
      writeAtomically(cached, bytes);
    }
    const result = { url, path: pin.path, sha256: pin.sha256, bytes, text: bytes.toString("utf8") };
    this.cache.set(cacheKey, result);
    return result;
  }

  /**
   * Both npm packages, verified and extracted into <tmp>/node_modules/{tr46,punycode}, so tr46's
   * require("punycode/") resolves to the userland package and never to Node's built-in.
   * Returns { tr46, punycode }, each { dir, version, integrity, members: {name: sha256}, read(member) },
   * and tr46.load(), which requires tr46's index.js from there.
   */
  packages() {
    if (this.extracted) return this.extracted;
    // The real path, because require.resolve reports one (on macOS, /var is /private/var).
    const tmp = realpathSync(mkdtempSync(path.join(os.tmpdir(), "swift-tr46-sources-")));
    process.once("exit", () => rmSync(tmp, { recursive: true, force: true }));
    const result = {};
    for (const [key, pin, override] of [
      ["tr46", TR46, this.options.tr46Tarball],
      ["punycode", PUNYCODE, this.options.punycodeTarball],
    ]) {
      const tarball = this.#tarball(pin, override);
      const dir = path.join(tmp, "node_modules", pin.name);
      mkdirSync(dir, { recursive: true });
      // Extract the verified bytes, not the file on disk, which could change after the check.
      const copy = path.join(tmp, `${pin.name}-${pin.version}.tgz`);
      writeFileSync(copy, tarball);
      execFileSync("tar", ["-xzf", copy, "-C", dir, "--strip-components=1"], { stdio: ["ignore", "ignore", "inherit"] });
      const members = {};
      for (const [member, expected] of Object.entries(pin.members)) {
        const file = path.join(dir, member);
        if (!existsSync(file)) fail(`${pin.name}-${pin.version}.tgz has no package/${member}`);
        const actual = sha256(readFileSync(file));
        if (actual !== expected) {
          fail(`checksum mismatch for package/${member} in ${pin.name}-${pin.version}.tgz: SHA-256 ${actual}, expected ${expected}`);
        }
        members[member] = actual;
      }
      const manifest = JSON.parse(readFileSync(path.join(dir, "package.json"), "utf8"));
      if (manifest.name !== pin.name || manifest.version !== pin.version) {
        fail(`${pin.name}-${pin.version}.tgz holds ${manifest.name}@${manifest.version}`);
      }
      if (pin.unicodeVersion !== undefined && manifest.unicodeVersion !== pin.unicodeVersion) {
        fail(`${pin.name}'s unicodeVersion is ${manifest.unicodeVersion}, expected ${pin.unicodeVersion}`);
      }
      result[key] = {
        dir,
        name: pin.name,
        version: pin.version,
        integrity: pin.integrity,
        members,
        read: (member) => {
          if (!(member in members)) fail(`package/${member} of ${pin.name} is not pinned`);
          return readFileSync(path.join(dir, member));
        },
      };
    }
    const requireFromTr46 = createRequire(path.join(result.tr46.dir, "index.js"));
    const punycodeEntry = requireFromTr46.resolve("punycode/");
    if (path.dirname(punycodeEntry) !== result.punycode.dir) fail(`tr46 resolves punycode to ${punycodeEntry}`);
    result.tr46.require = requireFromTr46;
    result.tr46.load = () => requireFromTr46("./index.js");
    this.extracted = result;
    return result;
  }

  /** The .tgz bytes, verified against the pinned sha512, from --*-tarball, the cache or npm pack. */
  #tarball(pin, override) {
    const name = `${pin.name}-${pin.version}.tgz`;
    let file = override;
    if (!file) {
      file = path.join(this.dataDir, "npm", name);
      if (!existsSync(file)) this.#npmPack(pin, file);
    }
    if (!existsSync(file)) fail(`${file} does not exist`);
    const bytes = readFileSync(file);
    const actual = sha512Integrity(bytes);
    if (actual !== pin.integrity) {
      fail(`checksum mismatch for ${file}: ${actual}, expected ${pin.integrity}. Delete the file to fetch it again.`);
    }
    return bytes;
  }

  #npmPack(pin, file) {
    mkdirSync(path.dirname(file), { recursive: true });
    const staging = mkdtempSync(path.join(path.dirname(file), ".npm-pack-"));
    try {
      const output = execFileSync(
        "npm",
        ["pack", `${pin.name}@${pin.version}`, "--pack-destination", staging, "--json", "--ignore-scripts"],
        { cwd: staging, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }
      );
      const [info] = JSON.parse(output);
      if (info?.integrity !== pin.integrity) fail(`npm pack ${pin.name}@${pin.version} reports ${info?.integrity}, expected ${pin.integrity}`);
      const packed = path.join(staging, info.filename);
      const actual = sha512Integrity(readFileSync(packed));
      if (actual !== pin.integrity) fail(`checksum mismatch for the packed ${info.filename}: ${actual}, expected ${pin.integrity}`);
      renameSync(packed, file);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }

  /** Obtains and verifies every pinned source, and prints what it checked. */
  async fetchAll() {
    const { tr46, punycode } = this.packages();
    console.log(`[sources] ${tr46.name} ${tr46.version}: ${tr46.integrity}, ${Object.keys(tr46.members).length} members verified`);
    console.log(`[sources] ${punycode.name} ${punycode.version}: ${punycode.integrity}, ${Object.keys(punycode.members).length} members verified`);
    for (const key of Object.keys(UNICODE.files)) {
      const file = await this.unicode(key);
      console.log(`[sources] Unicode ${UNICODE.version} ${file.path}: ${file.bytes.length} bytes, SHA-256 verified`);
    }
    for (const key of Object.keys(WPT.files)) {
      const file = await this.wpt(key);
      console.log(`[sources] WPT ${WPT.commit.slice(0, 7)} ${file.path}: ${file.bytes.length} bytes, SHA-256 verified`);
    }
  }
}

/** `node -e 'import("./Scripts/lib/sources.mjs").then((m) => m.fetchAll())'` */
export async function fetchAll(argv = []) {
  await run("sources", async () => {
    await new Sources(parseArgs(argv)).fetchAll();
  });
}
