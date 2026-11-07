#!/usr/bin/env bash
# Rebuild the engine/ vendor branches used to integrate Zen and Glide.
#
# `surfer download` leaves engine/ as a git repo whose root commit is pristine
# Firefox. Both forks distribute their changes as patches against that same
# base, so replaying each fork's patch set onto its own branch turns
# integration into an ordinary 3-way merge on real source files. The
# alternative is diffing the .patch files against each other, which produces
# diffs of diffs that cannot be merged or reviewed.
#
# Branches produced:
#   vendor/zen    base + Zen's own src/**/*.patch, at the commit from zen_ref
#   vendor/glide  base + Glide's src/**/*.patch, minus excluded groups
#   enso          vendor/zen with vendor/glide merged in
#
# vendor/zen reads Zen's patches from the zen remote rather than from this
# repo's src/, because export-patches.sh writes the merge result back into
# src/. After the first sync, this repo's patches already contain Glide.
#
# Both vendor branches are disposable. Never commit work to them; they are
# regenerated from scratch on every upstream sync. Conflict resolutions are
# remembered by git rerere, whose cache lives in .rr-cache/ so that it survives
# the engine/ wipe that a Firefox version bump performs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/enso/lib.sh"
ENGINE="$ROOT/engine"
REPORTS="$ROOT/.enso-reports"
# Not named GROUPS: bash reserves that for the caller's group-id array.
PATCH_GROUPS="$ROOT/scripts/enso/glide-patch-groups.tsv"
EXCLUDED_GROUPS="$ROOT/scripts/enso/glide-excluded-groups.txt"

[ -d "$ENGINE/.git" ] || { echo "engine/ is not a git repo; run 'npm run download' first" >&2; exit 1; }
[ -d "$GLIDE/src" ] || { echo "no Glide checkout at $GLIDE; run 'git submodule update --init'" >&2; exit 1; }

mkdir -p "$REPORTS"

git_engine() { git -C "$ENGINE" "$@"; }

# A freshly downloaded engine/ has its own empty rr-cache, so point it at the
# committed one. Anything recorded there in the meantime is kept.
if [ ! -L "$ENGINE/.git/rr-cache" ]; then
  for entry in "$ENGINE/.git/rr-cache"/*; do
    if [ -e "$entry" ] && [ ! -e "$ROOT/.rr-cache/${entry##*/}" ]; then
      cp -R "$entry" "$ROOT/.rr-cache/"
    fi
  done
  rm -rf "$ENGINE/.git/rr-cache"
  ln -s "$ROOT/.rr-cache" "$ENGINE/.git/rr-cache"
fi
git_engine config rerere.enabled true
git_engine config rerere.autoupdate true

patch_target() { grep -m1 '^diff --git' "$1" | sed 's|^diff --git a/||; s| b/.*||'; }

# A few patches on both sides create new files, which `reset --hard` leaves
# behind; on the next run they fail with "would create the file, which already
# exists". `clean -fd` (deliberately without -x) removes them while respecting
# .gitignore. That distinction matters once surfer's overlay symlinks are in
# place, which is why this script must run before `npm run import`, not after.
reset_engine_to_base() {
  git_engine reset --hard "$BASE" --quiet
  git_engine clean -fdq
}

active_groups() { grep -vE '^[[:space:]]*(#|$)' "$EXCLUDED_GROUPS"; }

# Patches only ever modify files that already exist upstream: both surfer and
# Glide generate them with `git diff <path>`, and new files ship through the
# src/ overlay instead. Staging with -u therefore keeps the gitignored overlay
# symlinks out of the vendor commits.
commit_tracked() { git_engine add -u && git_engine commit -qm "$1" --allow-empty; }

# An unclassified patch means Glide added something upstream that nobody has
# looked at. Failing here is deliberate: the alternative is silently building
# it in.
verify_classified() {
  local unclassified=0 target
  while IFS= read -r patch_file; do
    target=$(patch_target "$patch_file")
    if ! awk -F'\t' -v t="$target" '$2==t {found=1} END {exit !found}' "$PATCH_GROUPS"; then
      echo "  unclassified patch target: $target" >&2
      unclassified=$((unclassified + 1))
    fi
  done < <(find "$GLIDE/src" -name '*.patch' | sort)

  [ "$unclassified" -eq 0 ] || {
    echo "$unclassified Glide patch(es) missing from $(basename "$PATCH_GROUPS"); classify them first" >&2
    exit 1
  }
}

build_exclusion_set() {
  local out="$1" group
  : > "$out"
  while IFS= read -r group; do
    awk -F'\t' -v g="$group" '$1==g {print $2}' "$PATCH_GROUPS" >> "$out"
  done < <(active_groups)
  sort -u -o "$out" "$out"
}

apply_patch_set() {
  local src_dir="$1" label="$2" exclusions="${3:-}"
  local report="$REPORTS/$label.tsv"
  local clean=0 fuzzy=0 failed=0 skipped=0 target status

  : > "$report"

  while IFS= read -r patch_file; do
    target=$(patch_target "$patch_file")

    if [ -n "$exclusions" ] && grep -qxF "$target" "$exclusions"; then
      printf 'skipped\t%s\t%s\n' "$target" "${patch_file#"$ROOT"/}" >> "$report"
      skipped=$((skipped + 1))
      continue
    fi

    if git_engine apply --ignore-space-change --ignore-whitespace "$patch_file" 2>/dev/null; then
      status=clean; clean=$((clean + 1))
    elif patch -d "$ENGINE" -p1 -l -F3 -s --no-backup-if-mismatch -i "$patch_file" 2>/dev/null; then
      # git apply has no fuzzy context matching, so retry anything it rejects
      # with GNU patch before calling it a real failure.
      status=fuzzy; fuzzy=$((fuzzy + 1))
    else
      status=FAILED; failed=$((failed + 1))
    fi

    printf '%s\t%s\t%s\n' "$status" "$target" "${patch_file#"$ROOT"/}" >> "$report"
  done < <(find "$src_dir" -name '*.patch' | sort)

  echo "  $label: clean=$clean fuzzy=$fuzzy failed=$failed skipped=$skipped  -> ${report#"$ROOT"/}"
}

echo "verifying Glide patch classification"
verify_classified
echo "  excluded groups: $(active_groups | tr '\n' ' ')"

EXCLUSIONS="$REPORTS/excluded-paths.txt"
build_exclusion_set "$EXCLUSIONS"
echo "  excluded patches: $(wc -l < "$EXCLUSIONS" | tr -d ' ')"

BASE=$(git_engine rev-list --max-parents=0 --all | head -1)
echo "pristine base: $BASE ($(git_engine log -1 --format=%s "$BASE"))"

ZEN_REF=$(zen_ref)
ZEN_SRC="$REPORTS/zen-src"
rm -rf "$ZEN_SRC"
mkdir -p "$ZEN_SRC"
git -C "$ROOT" archive "$ZEN_REF" src | tar -x -C "$ZEN_SRC"

echo "building vendor/zen from zen $(git -C "$ROOT" rev-parse --short "$ZEN_REF")"
git_engine switch -C vendor/zen "$BASE" --quiet
reset_engine_to_base
apply_patch_set "$ZEN_SRC/src" zen
commit_tracked "zen: $(git -C "$ROOT" rev-parse --short "$ZEN_REF")"

echo "building vendor/glide"
git_engine switch -C vendor/glide "$BASE" --quiet
reset_engine_to_base
apply_patch_set "$GLIDE/src" glide "$EXCLUSIONS"
commit_tracked "glide: $(git -C "$GLIDE" rev-parse --short HEAD)"

echo "merging into enso"
git_engine switch -C enso vendor/zen --quiet
git_engine merge --no-ff --no-commit vendor/glide >/dev/null 2>&1 || true

# git merge reports failure whenever it hit a conflict, even one that rerere
# went on to resolve and stage, so trust the unmerged-path list instead of the
# exit status.
git_engine diff --name-only --diff-filter=U > "$REPORTS/conflicts.txt"
remaining=$(wc -l < "$REPORTS/conflicts.txt" | tr -d ' ')

if [ "$remaining" -eq 0 ]; then
  git_engine commit -qm "merge vendor/glide into enso" || true
  echo "  merged cleanly (rerere resolved any known conflicts)"
else
  echo "  $remaining unresolved conflict(s) -> .enso-reports/conflicts.txt"
  echo "  resolve, then: git -C engine commit"
  exit 1
fi
