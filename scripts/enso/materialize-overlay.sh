#!/usr/bin/env bash
# Copy the src/ overlay into engine/ as real files.
#
# Surfer symlinks src/ into engine/ with absolute targets, so an overlay file
# is reached as:
#
#   objdir/dist/.../ZenGlanceChild.sys.mjs
#     -> engine/zen/glance/actors/ZenGlanceChild.sys.mjs
#     -> src/zen/glance/actors/ZenGlanceChild.sys.mjs
#
# The final target sits outside engine/. Content processes may only read the
# repo dir (engine/, from Info.plist MozillaDeveloperRepoPath) and the objdir:
# ContentParent.cpp whitelists exactly those, and while SandboxPolicyContent.h
# allows file-read-metadata everywhere so the links resolve, file-read-data is
# checked against the resolved path. Every JSWindowActor child is therefore
# denied, silently — Firefox reports only "Failed to load resource:///actors/…".
#
# This affects Zen's own actors (ZenGlance, ZenBoosts, ZenWindowDrag) exactly as
# much as Glide's. Glide sidesteps it upstream by copying rather than
# symlinking (scripts/copy-src.mts); this is the same idea.
#
# Driven from src/ rather than from engine/ symlinks so that it stays correct
# on re-runs: once a file has been materialised the symlink is gone, and a
# link-driven pass would have no way to find its source again. Surfer maps
# src/<path> to engine/<path> one-to-one, so the counterpart is derivable.
#
# Run after `npm run import`, and again after editing anything under src/,
# before `mach build`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="$ROOT/engine"
SRC="$ROOT/src"

[ -d "$ENGINE" ] || { echo "no engine/; run 'npm run download' first" >&2; exit 1; }

copied=0
unchanged=0

while IFS= read -r src_file; do
  rel="${src_file#"$SRC"/}"
  dest="$ENGINE/$rel"

  # src/browser/actors/ holds Glide's relative symlinks into
  # glide/browser/actors/dist/, which only resolve once Glide is built.
  [ -e "$src_file" ] || { echo "src/$rel is a dangling symlink; run build-glide.sh and sync-glide-overlay.sh" >&2; exit 1; }

  # A symlink still resolving inside engine/ is fine for the sandbox, but a
  # symlink out of tree is not, and a stale copy needs refreshing.
  if [ -L "$dest" ]; then
    target=$(readlink -f "$dest" 2>/dev/null || true)
    case "$target" in "$ENGINE"/*) unchanged=$((unchanged + 1)); continue ;; esac
    rm "$dest"
  elif [ -e "$dest" ]; then
    if cmp -s "$src_file" "$dest"; then
      unchanged=$((unchanged + 1))
      continue
    fi
  else
    # Surfer overlays every non-patch file in src/, but only during import, so
    # anything generated since then (Glide's dist/ output) has no engine/
    # counterpart yet. Add it the way surfer would, including the
    # engine/.gitignore entry that keeps vendor-branches.sh's `git clean` off it.
    mkdir -p "$(dirname "$dest")"
    grep -qxF "$rel" "$ENGINE/.gitignore" || printf '\n%s' "$rel" >> "$ENGINE/.gitignore"
  fi

  # -L because some src/ entries are themselves symlinks, and the copy must
  # hold content for the sandbox to read it.
  cp -pL "$src_file" "$dest"
  copied=$((copied + 1))
done < <(find "$SRC" \( -type f -o -type l \) ! -name '*.patch' ! -path '*/node_modules/*')

echo "copied $copied file(s), $unchanged already current"
