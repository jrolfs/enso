#!/usr/bin/env bash
# Regenerate the Zen and Glide integration and prepare engine/ for a build.
#
# Run after sync-zen.sh, after sync-glide.sh, or after changing the Glide patch
# groups. Re-downloads Firefox when surfer.json names a version engine/ was not
# set up from, rebuilds the vendor branches, exports the merged patches into
# src/, then resets engine/ to pristine Firefox before importing, because
# surfer's import fails over an already-patched tree.
#
# When vendor-branches.sh stops on a conflict, resolve it in engine/, commit
# there, and re-run this script. rerere records the resolution on that commit
# and replays it from then on.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="$ROOT/engine"
cd "$ROOT"

wanted=$(jq -r .version.version surfer.json)

# Surfer names engine/'s pristine root branch after the Firefox version.
if ! git -C "$ENGINE" rev-parse --verify --quiet "refs/heads/$wanted" >/dev/null 2>&1; then
  echo "engine/ is not Firefox $wanted; replacing it, which discards the objdir too"
  rm -rf "$ENGINE"
  npm run download
fi

bash scripts/enso/vendor-branches.sh
bash scripts/enso/export-patches.sh

# Surfer applies patches as uncommitted changes on a branch named after
# surfer.json's "name", so put engine/ back in the state import expects.
git -C "$ENGINE" switch --quiet --force-create zen_browser "refs/heads/$wanted"
git -C "$ENGINE" clean -fdq

npm run import
bash scripts/enso/materialize-overlay.sh

echo
echo "next: npm run build"
