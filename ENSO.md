# Ensō

Zen Browser with Glide's keyboard layer and TypeScript configuration grafted
in. Zen supplies the UI, Glide supplies modal keybindings, hints, excmds and a
config file you write in TypeScript.

Kept in a separate file from `README.md` so that syncing Zen upstream does not
conflict here.

## Layout

Three sibling checkouts. Only this one is built.

```
enso/
  enso/         this fork
  zen-browser/  upstream reference, never built in
  glide/        upstream reference, also the Glide build workspace
```

The path must stay ASCII. The Nix clang wrapper mangles non-ASCII characters
in paths and every Rust link fails.

## Build and run

`direnv` activates devenv on `cd`.

```bash
npm ci
npm run download
npm run import
bash scripts/enso/materialize-overlay.sh
npm run build
cd engine && ./mach run
```

`materialize-overlay.sh` is required, not optional. It copies the `src/`
overlay into `engine/` as real files so that content-process reads stay inside
the sandbox's allowed paths. Without it the browser builds but every
JSWindowActor child fails to load. Re-run it after editing anything in `src/`.

Incremental rebuilds are about 20 seconds. A clean build is about 45 minutes.

`npm run import` is not idempotent and fails on a Zen patch when the tree is
already patched. When only `src/` changed, skip it and run `./mach build`.

## How the graft works

Both Zen and Glide distribute their changes as patches against pristine
Firefox, so integration happens in `engine/` as an ordinary 3-way merge rather
than by diffing patch files against each other.

| | |
|---|---|
| `scripts/enso/vendor-branches.sh` | replays each fork's patches onto its own branch, then merges |
| `scripts/enso/export-patches.sh` | writes the merged result back to `src/**/*.patch` |
| `scripts/enso/sync-glide-overlay.sh` | copies Glide's non-patch files into `src/` |
| `scripts/enso/materialize-overlay.sh` | copies `src/` into `engine/` as real files |
| `scripts/enso/glide-patch-groups.tsv` | classifies every Glide patch; unclassified patches fail the build |
| `scripts/enso/glide-excluded-groups.txt` | which groups to skip, including a toggle for the vim caret |

`.rr-cache/` holds recorded merge conflict resolutions. It lives outside
`engine/` because a Firefox version bump deletes that directory.

`scripts/enso/glide-fixes/` carries fixes to Glide itself. They are applied to
the Glide checkout before its build, and are candidates to send upstream.

Full reasoning for every decision is in [DECISIONS.md](DECISIONS.md).

## Status

Builds and runs. Zen's UI is intact, Glide's config loads, and the two
keyboard systems coexist without conflicting because vim bindings are bare
letters while browser shortcuts are modified keys.

Known issues:

- The mode indicator appears without text when switching tabs.
- The resting mode strip is low contrast against pages with white backgrounds.
- Excmds are not yet reachable from Zen's command palette.

Nothing is published. The fork has no `origin` remote; `zen` and `glide` point
at the two upstreams.
