# shellcheck shell=bash disable=SC2034
# Shared by the scripts in scripts/enso/. Source it after setting ROOT.

GLIDE="$ROOT/vendor/glide"
ZEN_BRANCH="${ZEN_BRANCH:-dev}"

# Prints the Zen commit this tree is built from: the commit being merged while
# a sync-zen.sh merge is still open, otherwise the last one merged.
zen_ref() {
  git -C "$ROOT" rev-parse --verify --quiet "zen/$ZEN_BRANCH" >/dev/null || {
    echo "no zen/$ZEN_BRANCH; run 'git remote add zen https://github.com/zen-browser/desktop.git && git fetch zen'" >&2
    return 1
  }
  local head
  head=$(git -C "$ROOT" rev-parse --verify --quiet MERGE_HEAD || git -C "$ROOT" rev-parse HEAD)
  git -C "$ROOT" merge-base "$head" "zen/$ZEN_BRANCH"
}
