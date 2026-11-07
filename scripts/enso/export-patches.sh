#!/usr/bin/env bash
# Regenerate src/**/*.patch from the merged engine/ enso branch.
#
# The vendor-branch merge lives in git, but the build reads src/**/*.patch, so
# the merge result has to be written back out. Every patch is first reset to
# Zen's own, then the files the merge changed relative to vendor/zen are
# exported over them. That makes the patch set a function of the Zen commit
# and the enso branch alone: a merged patch whose Glide side has gone reverts
# to Zen's, and a Glide-only patch that Glide dropped is deleted. Enso carries
# no Firefox patches of its own, which is what makes the reset safe.
#
# Patch filenames follow surfer's convention (dots in the basename become
# dashes), because surfer's own `export` will overwrite these in place later.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/enso/lib.sh"
ENGINE="$ROOT/engine"
REPORTS="$ROOT/.enso-reports"

git_engine() { git -C "$ENGINE" "$@"; }

for branch in vendor/zen enso; do
  git_engine rev-parse --verify --quiet "$branch" >/dev/null \
    || { echo "missing branch $branch; run vendor-branches.sh first" >&2; exit 1; }
done

mkdir -p "$REPORTS"

BASE=$(git_engine rev-list --max-parents=0 --all | head -1)

patch_path_for() {
  local target="$1"
  local dir base
  dir=$(dirname "$target")
  base=$(basename "$target" | tr '.' '-')
  if [ "$dir" = "." ]; then
    echo "$ROOT/src/$base.patch"
  else
    echo "$ROOT/src/$dir/$base.patch"
  fi
}

ZEN_REF=$(zen_ref)
ZEN_SRC=$(mktemp -d)
trap 'rm -rf "$ZEN_SRC"' EXIT
git -C "$ROOT" archive "$ZEN_REF" src | tar -x -C "$ZEN_SRC"

find "$ROOT/src" -name '*.patch' -delete
while IFS= read -r rel; do
  mkdir -p "$ROOT/$(dirname "$rel")"
  cp -p "$ZEN_SRC/$rel" "$ROOT/$rel"
done < <(cd "$ZEN_SRC" && find src -name '*.patch')

written=0
while IFS= read -r target; do
  out=$(patch_path_for "$target")
  mkdir -p "$(dirname "$out")"
  git_engine diff --src-prefix=a/ --dst-prefix=b/ --full-index "$BASE" enso -- "$target" > "$out"
  [ -s "$out" ] || { rm -f "$out"; continue; }
  written=$((written + 1))
  printf '%s\n' "${out#"$ROOT"/}"
done < <(git_engine diff --name-only vendor/zen enso) > "$REPORTS/exported.txt"

echo "exported $written patch(es) -> .enso-reports/exported.txt"
