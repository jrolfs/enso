#!/usr/bin/env bash
# Regenerate src/**/*.patch from the merged engine/ enso branch.
#
# The vendor-branch merge lives in git, but the build reads src/**/*.patch, so
# the merge result has to be written back out. Only files that the merge
# actually changed relative to vendor/zen are exported; the rest of Zen's
# patch set is left untouched so this never rewrites 256 files it did not
# need to.
#
# Patch filenames follow surfer's convention (dots in the basename become
# dashes), because surfer's own `export` will overwrite these in place later.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
