/**
 * emit.mjs
 *
 * Output formats shared by the generators: Swift array literals and comments, and the
 * one-vector-per-line JSON used for test data. Everything here is deterministic: no timestamps,
 * no locale, fixed ordering.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fail, ROOT } from "./sources.mjs";

// ── Swift ──────────────────────────────────────────────────────────────────────

/** Upper-case hex literal. */
export const hex = (n) => `0x${n.toString(16).toUpperCase()}`;

const SWIFT_LIMITS = { UInt8: 0xff, UInt32: 0xffffffff, UInt64: Number.MAX_SAFE_INTEGER };

/** `static let name: [type] = [ … ]`, 12 hex values per line, under a one-line doc comment. */
export function swiftArray(doc, name, type, values) {
  const limit = SWIFT_LIMITS[type];
  if (limit === undefined) fail(`no Swift type ${type}`);
  for (const value of values) {
    if (!Number.isSafeInteger(value) || value < 0 || value > limit) fail(`${name}: ${value} doesn't fit ${type}`);
  }
  const lines = [`    /// ${doc}`, `    static let ${name}: [${type}] = [`];
  for (let i = 0; i < values.length; i += 12) {
    lines.push(`        ${values.slice(i, i + 12).map(hex).join(", ")},`);
  }
  lines.push("    ]");
  return lines.join("\n");
}

/** `static let name = "value"`. */
export function swiftString(name, value) {
  if (!/^[\x20-\x7e]*$/.test(value) || /["\\]/.test(value)) fail(`${name}: ${JSON.stringify(value)} needs escaping`);
  return `    static let ${name} = "${value}"`;
}

/** Text as `//` comment lines, with blank lines kept as a bare `//`. */
export const swiftComment = (text) =>
  text
    .replace(/\n+$/, "")
    .split("\n")
    .map((line) => (line ? `// ${line}`.trimEnd() : "//"))
    .join("\n");

/** The Unicode License V3, as https://www.unicode.org/license.txt and NOTICE reproduce it. */
export const UNICODE_LICENSE_V3 = `UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
`;

// ── JSON ───────────────────────────────────────────────────────────────────────

/** JSON with every UTF-16 unit above U+007E written as a lower-case \uXXXX escape. */
export const asciiJSON = (value) =>
  JSON.stringify(value).replace(/[\u007f-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);

/**
 * A vector file: each header key on its own line, then each array with one element per line.
 * `header` and `arrays` are plain objects; their key order is the file's order.
 */
export function vectorFile(header, arrays) {
  const keys = [...Object.keys(header), ...Object.keys(arrays)];
  if (new Set(keys).size !== keys.length) fail(`duplicate top-level key in ${keys.join(", ")}`);
  const lines = ["{"];
  const entries = Object.entries(arrays);
  for (const [key, value] of Object.entries(header)) {
    lines.push(`  ${asciiJSON(key)}: ${asciiJSON(value)}${entries.length > 0 ? "," : ""}`);
  }
  entries.forEach(([name, rows], k) => {
    lines.push(`  ${asciiJSON(name)}: [`);
    rows.forEach((row, i) => lines.push(`    ${asciiJSON(row)}${i + 1 < rows.length ? "," : ""}`));
    lines.push(k + 1 < entries.length ? "  ]," : "  ]");
  });
  lines.push("}");
  const output = `${lines.join("\n")}\n`;
  if (/[^\x0a\x20-\x7e]/.test(output)) fail("a vector file holds a character outside printable ASCII");
  JSON.parse(output);
  return output;
}

// ── Files ──────────────────────────────────────────────────────────────────────

/** Writes `content` to `relative` under the repo root and logs its size. */
export function writeOutput(tag, relative, content, summary = "") {
  const file = path.join(ROOT, relative);
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, content);
  console.log(`[${tag}] wrote ${relative}: ${summary ? `${summary}, ` : ""}${Buffer.byteLength(content)} bytes`);
}
