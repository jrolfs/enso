#!/usr/bin/env bash
# Build Glide's generated sources in the vendor/glide submodule.
#
# src/glide/**/dist/, src/glide/bundled/ and the tutor page are build outputs
# that Glide gitignores, but jar.mn and the src/browser/actors/ symlinks
# reference them literally, so they must exist before sync-glide-overlay.sh
# copies Glide into src/. Enso's fixes are applied first so that both the
# copied sources and the compiled output include them.
#
# Safe to re-run: fixes that are already applied are skipped.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/enso/lib.sh"

[ -d "$GLIDE/src" ] || { echo "no Glide checkout at $GLIDE; run 'git submodule update --init'" >&2; exit 1; }

for fix in "$ROOT"/scripts/enso/glide-fixes/*.patch; do
  if git -C "$GLIDE" apply --reverse --check "$fix" 2>/dev/null; then
    echo "already applied: ${fix#"$ROOT"/}"
  elif git -C "$GLIDE" apply "$fix" 2>/dev/null; then
    echo "applied: ${fix#"$ROOT"/}"
  # --3way leaves conflict markers to resolve when a Glide update moves the
  # code a fix touches, rather than rejecting the whole patch.
  elif git -C "$GLIDE" apply --3way "$fix"; then
    echo "applied with a 3-way merge: ${fix#"$ROOT"/}"
  else
    echo "${fix#"$ROOT"/} conflicts with this Glide. Resolve the markers in vendor/glide," >&2
    echo "regenerate the fix with 'git -C vendor/glide diff HEAD > ${fix#"$ROOT"/}', and re-run." >&2
    exit 1
  fi
done

cd "$GLIDE"
export PATH="$GLIDE/scripts/bin:$PATH"
pnpm install --frozen-lockfile
pnpm build:ts
pnpm bundle
# glide.jar references tutor/dist/index.html, which build:ts does not produce.
pnpm build:docs:html
