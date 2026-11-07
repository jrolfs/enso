#!/usr/bin/env bash
# Move the vendor/glide submodule to another Glide commit or tag, then rebuild
# Glide and bring src/ up to date with it.
#
# Usage: sync-glide.sh <ref>
#
# Then run integrate.sh to regenerate the Firefox patches, build, and commit
# the moved submodule together with everything it changed under src/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/enso/lib.sh"

[ $# -eq 1 ] || { echo "usage: $0 <glide ref>" >&2; exit 1; }
ref="$1"

[ -d "$GLIDE/src" ] || { echo "no Glide checkout at $GLIDE; run 'git submodule update --init'" >&2; exit 1; }

git -C "$GLIDE" fetch --quiet --tags origin

# The checkout carries glide-fixes/ as uncommitted changes, which would block
# the checkout. Stash rather than discard, so anything else edited there is
# recoverable; build-glide.sh reapplies the fixes.
if [ -n "$(git -C "$GLIDE" status --porcelain --untracked-files=no)" ]; then
  git -C "$GLIDE" stash push --quiet -m "enso: before sync to $ref"
  echo "stashed vendor/glide changes (git -C vendor/glide stash list)"
fi

git -C "$GLIDE" checkout --quiet --detach "$ref"
echo "vendor/glide now at $(git -C "$GLIDE" describe --tags --always)"

bash "$ROOT/scripts/enso/build-glide.sh"
bash "$ROOT/scripts/enso/sync-glide-overlay.sh"
