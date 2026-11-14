# shellcheck shell=bash disable=SC2034
# Shared by the scripts in scripts/enso/. Source it after setting ROOT.

GLIDE="$ROOT/vendor/glide"
ZEN_BRANCH="${ZEN_BRANCH:-dev}"

# Prints the Zen commit this tree is built from, as recorded in .zen-sync-base.
# During an uncommitted sync-zen.sh run, that is already the commit being
# synced to.
zen_ref() {
  local ref
  ref=$(cat "$ROOT/.zen-sync-base")
  git -C "$ROOT" cat-file -e "$ref^{commit}" 2>/dev/null || {
    echo "Zen commit $ref is missing; run 'git remote add zen https://github.com/zen-browser/desktop.git && git fetch zen'" >&2
    return 1
  }
  echo "$ref"
}
