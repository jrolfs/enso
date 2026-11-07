# Ensō

Zen Browser with Glide's keyboard layer and TypeScript configuration grafted
in. Zen supplies the UI, Glide supplies modal keybindings, hints, excmds and a
config file you write in TypeScript.

Kept in a separate file from `README.md` so that syncing Zen upstream does not
conflict here.

## Layout

This repo is a fork of Zen, with Glide pinned as a submodule.

| | |
|---|---|
| `src/` | the overlay surfer applies to Firefox: Zen's, with Glide's copied in |
| `vendor/glide/` | Glide at the pinned commit, and the workspace for Glide's own build |
| `engine/` | Firefox source, created by `npm run download` and gitignored |

Zen upstream is the `zen` remote rather than a checkout, because this repo
already is Zen. Remotes are not cloned, so add it once:

```bash
git remote add zen https://github.com/zen-browser/desktop.git
```

The path must stay ASCII. The Nix clang wrapper mangles non-ASCII characters
in paths and every Rust link fails.

## Build and run

`direnv` activates devenv on `cd`.

```bash
git clone --recurse-submodules git@github.com:jrolfs/enso.git
cd enso
npm ci
bash scripts/enso/build-glide.sh
bash scripts/enso/sync-glide-overlay.sh
npm run download
npm run import
bash scripts/enso/materialize-overlay.sh
npm run build
cd engine && ./mach run
```

For a clone made without `--recurse-submodules`, run
`git submodule update --init` first.

`build-glide.sh` and `sync-glide-overlay.sh` produce files that Glide
gitignores but this build needs: compiled `.mjs` under `**/dist/`, bundled
dependencies, and the tutor page. `src/browser/actors/` holds symlinks into
that output, so surfer fails with `ENOENT` until it exists.

`npm run download` fetches the Firefox version pinned in `surfer.json`. Surfer
warns when a newer Firefox exists. Ignore that and do not run `surfer update`:
Firefox bumps arrive with Zen upstream, which also updates its patches for the
new version.

`materialize-overlay.sh` is required, not optional. It copies the `src/`
overlay into `engine/` as real files so that content-process reads stay inside
the sandbox's allowed paths. Without it the browser builds but every
JSWindowActor child fails to load. Re-run it after editing anything in `src/`
or rebuilding Glide.

Incremental rebuilds are about 20 seconds. A clean build is about 45 minutes.

`npm run import` is not idempotent and fails on a Zen patch when the tree is
already patched. When only `src/` changed, skip it and run `./mach build`.

## Updating

```bash
bash scripts/enso/sync-zen.sh             # merges zen/dev and leaves the merge open
bash scripts/enso/sync-glide.sh 0.1.65a   # moves Glide to a release
bash scripts/enso/integrate.sh            # regenerates patches, prepares engine/
npm run build
git commit                                # concludes the merge
```

Either sync can run alone. Pick a Glide release whose Firefox version, in
`vendor/glide/firefox.json`, is close to the one in Zen's `surfer.json`.

`sync-zen.sh` takes Zen's side of every conflicting patch, because
`export-patches.sh` regenerates them all from Zen's set anyway. A conflict
anywhere else is an Enso edit to a Zen file, so far only `.gitignore` and
`tools/ffprefs/src/main.rs`, and needs resolving by hand.

When the Firefox version changes, `integrate.sh` replaces `engine/`, so the
build that follows is a clean one. If `vendor-branches.sh` stops on a
conflict, resolve it in `engine/`, commit there, and re-run `integrate.sh`.

## How the graft works

Both Zen and Glide distribute their changes as patches against pristine
Firefox, so integration happens in `engine/` as an ordinary 3-way merge rather
than by diffing patch files against each other.

| | |
|---|---|
| `scripts/enso/sync-zen.sh` | merges Zen upstream, resolving patch conflicts to Zen's side |
| `scripts/enso/sync-glide.sh` | moves the Glide submodule, then builds and syncs it |
| `scripts/enso/integrate.sh` | re-downloads Firefox on a version change, then vendors, exports, imports and materializes |
| `scripts/enso/vendor-branches.sh` | replays each fork's patches onto its own branch, then merges |
| `scripts/enso/export-patches.sh` | writes the merged result back to `src/**/*.patch` |
| `scripts/enso/build-glide.sh` | applies `glide-fixes/` to `vendor/glide` and runs Glide's build |
| `scripts/enso/sync-glide-overlay.sh` | copies Glide's non-patch files and build output into `src/` |
| `scripts/enso/materialize-overlay.sh` | copies `src/` into `engine/` as real files |
| `scripts/enso/glide-patch-groups.tsv` | classifies every Glide patch; unclassified patches fail the build |
| `scripts/enso/glide-excluded-groups.txt` | which groups to skip, including a toggle for the vim caret |

`.rr-cache/` holds recorded merge conflict resolutions. It lives outside
`engine/` because a Firefox version bump deletes that directory.

`scripts/enso/glide-fixes/` carries fixes to Glide itself. `build-glide.sh`
applies them to `vendor/glide` before building, which is why the submodule is
always dirty and `.gitmodules` sets `ignore = dirty`. Change Glide's files
there, never in `src/glide/`, because every sync overwrites `src/glide/`. The
fixes are candidates to send upstream.

Full reasoning for every decision is in [DECISIONS.md](DECISIONS.md).

## Status

Builds and runs. Zen's UI is intact, Glide's config loads, and the two
keyboard systems coexist without conflicting because vim bindings are bare
letters while browser shortcuts are modified keys.

Known issues:

- The mode indicator appears without text when switching tabs.
- The resting mode strip is low contrast against pages with white backgrounds.
- Excmds are not yet reachable from Zen's command palette.

The fork is pushed to `origin` (`jrolfs/enso`), but no builds are published.
