#!/usr/bin/env bash
# Copy Glide's non-patch source files into src/.
#
# Glide ships two kinds of change: patches against upstream Firefox (handled by
# vendor-branches.sh + export-patches.sh) and whole new files that land in the
# src/ overlay. This script handles the second kind. Zen never writes to any of
# these paths, so they copy in without conflict.
#
# The copy overwrites, which is safe because Enso's changes to Glide's files
# live in glide-fixes/ and are applied to the checkout by build-glide.sh. Edit
# them there, never in src/ directly, or the next sync reverts them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/enso/lib.sh"

[ -d "$GLIDE/src" ] || { echo "no Glide checkout at $GLIDE; run 'git submodule update --init'" >&2; exit 1; }

for fix in "$ROOT"/scripts/enso/glide-fixes/*.patch; do
  git -C "$GLIDE" apply --reverse --check "$fix" 2>/dev/null \
    || { echo "${fix#"$ROOT"/} is not applied to $GLIDE; run build-glide.sh first" >&2; exit 1; }
done

[ -d "$GLIDE/src/glide/bundled" ] || { echo "Glide is not built; run build-glide.sh first" >&2; exit 1; }

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

# A file Glide deleted since the committed pin would otherwise linger in src/
# and stay in the build. Patches are left to export-patches.sh.
removed=0
if pinned=$(git -C "$ROOT" rev-parse --verify --quiet HEAD:vendor/glide); then
  while IFS= read -r path; do
    rel="${path#src/}"
    should_skip "$rel" && continue
    if [ -e "$ROOT/src/$rel" ] || [ -L "$ROOT/src/$rel" ]; then
      rm "$ROOT/src/$rel"
      removed=$((removed + 1))
    fi
  done < <(git -C "$GLIDE" diff --name-only --no-renames --diff-filter=D "$pinned" HEAD -- src ':!*.patch')
fi

echo "copied $copied, skipped $skipped, removed $removed file(s) for glide $(git -C "$GLIDE" rev-parse --short HEAD)"
