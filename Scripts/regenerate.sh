#!/usr/bin/env bash
# Regenerates every generated file: Sources/TR46/Generated/*.swift and Tests/TR46Tests/Resources/*.json.
#
#   Scripts/regenerate.sh            # write them
#   Scripts/regenerate.sh --check    # write them, then fail if they differ from what is committed
#
# Any other argument goes to both generators (see Scripts/lib/sources.mjs): --tr46-tarball,
# --punycode-tarball, --unicode-dir, --data-dir, --fetch-only. Paths are resolved against the
# working directory.
#
# Safe for macOS's bash 3.2.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

check=0
args=()
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    *) args+=("$arg") ;;
  esac
done

expected="v$(tr -d '[:space:]' < "$root/.node-version")"
actual="$(node --version 2>/dev/null || true)"
if [ "$actual" != "$expected" ]; then
  echo "regenerate.sh: Node $expected is required, found ${actual:-no node}; see .node-version" >&2
  exit 1
fi

node "$root/Scripts/generate-tables.mjs" ${args[@]+"${args[@]}"}
node "$root/Scripts/generate-vectors.mjs" ${args[@]+"${args[@]}"}

if [ "$check" -eq 1 ]; then
  generated=(Sources/TR46/Generated Tests/TR46Tests/Resources)
  if ! git -C "$root" diff --exit-code --stat -- "${generated[@]}"; then
    echo "regenerate.sh: the generated files differ from the committed ones; run Scripts/regenerate.sh and commit the result" >&2
    exit 1
  fi
  untracked="$(git -C "$root" status --porcelain --untracked-files=all -- "${generated[@]}")"
  if [ -n "$untracked" ]; then
    echo "regenerate.sh: generated files are not committed:" >&2
    echo "$untracked" >&2
    exit 1
  fi
  echo "regenerate.sh: generated files match the committed ones"
fi
