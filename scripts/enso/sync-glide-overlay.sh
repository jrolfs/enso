#!/usr/bin/env bash
# Copy Glide's non-patch source files into src/.
#
# Glide ships two kinds of change: patches against upstream Firefox (handled by
# vendor-branches.sh + export-patches.sh) and whole new files that land in the
# src/ overlay. This script handles the second kind. Zen never writes to any of
# these paths, so they copy in without conflict.
#
# The synced Glide commit is recorded in .glide-sync-base. To pull a later
# Glide release with real 3-way merge semantics rather than a blind overwrite:
#
#   git fetch glide
#   git diff "$(cat .glide-sync-base)" glide/main -- src/glide | git apply -3
#
# Use that in preference to re-running this script once local adaptations
# exist, or they will be clobbered.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLIDE="${GLIDE_SRC:-$(cd "$ROOT/.." && pwd)/glide}"

[ -d "$GLIDE/src" ] || { echo "no Glide checkout at $GLIDE (override with GLIDE_SRC=)" >&2; exit 1; }

# Path prefixes to skip, keyed to excluded groups in glide-excluded-groups.txt.
# Only the `testing` group ships overlay files; every other excluded group is
# patches-only. Revisit this list when re-enabling a group.
SKIP_PREFIXES=(
  "testing/"
)

should_skip() {
  local rel="$1" prefix
  for prefix in "${SKIP_PREFIXES[@]}"; do
    case "$rel" in "$prefix"*) return 0 ;; esac
  done
  return 1
}

copied=0
skipped=0
while IFS= read -r abs; do
  rel="${abs#"$GLIDE"/src/}"

  if should_skip "$rel"; then
    skipped=$((skipped + 1))
    continue
  fi

  dest="$ROOT/src/$rel"
  mkdir -p "$(dirname "$dest")"
  # -P, and -type l below: src/browser/actors/ holds seven relative symlinks
  # into ../../glide/browser/actors/dist/. Dereferencing them would snapshot
  # stale build output, and skipping them leaves browser/actors/moz.build
  # registering actors whose files do not exist, which fails the build with a
  # SandboxValidationError. Our src/ mirrors Glide's layout, so the relative
  # targets stay correct when copied verbatim.
  cp -Pp "$abs" "$dest"
  copied=$((copied + 1))
done < <(find "$GLIDE/src" \( -type f -o -type l \) ! -name '*.patch')

git -C "$GLIDE" rev-parse HEAD > "$ROOT/.glide-sync-base"

echo "copied $copied file(s), skipped $skipped"
echo "glide base recorded: $(cut -c1-12 < "$ROOT/.glide-sync-base")"
echo
echo "note: src/glide/**/dist/ and src/glide/bundled/ are build outputs and are"
echo "      not in Glide's git tree. Run Glide's build-ts.mts and bundle.mts"
echo "      before building, or chrome:// URLs in jar.mn will not resolve."
