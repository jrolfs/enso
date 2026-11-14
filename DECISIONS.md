# Ensō integration decisions

Running log of judgement calls made while grafting Glide onto Zen. Each entry
records what was decided and why, so the reasoning survives the next Firefox
version bump.

Repo layout: this repo is a fork of Zen, with Zen upstream as the `zen` remote.
Glide is the `vendor/glide` submodule, which is never built into the browser
directly but is where Glide's own build runs.

---

## Architecture

### Integrate in `engine/`, not by diffing patch files

`surfer download` leaves `engine/` as a git repo whose root commit is pristine
Firefox 156.0.1. Both forks ship changes as patches against that same base, so
replaying each fork's patch set onto its own branch makes integration a normal
3-way merge on real source. The alternative — diffing Glide's `.patch` files
against their older selves — produces diffs of diffs that cannot be merged or
reviewed.

Branches: `156.0.1` (pristine) → `vendor/zen`, `vendor/glide` → `enso`.
Both vendor branches are disposable and regenerated on every sync; never commit
work to them. Driver: `scripts/enso/vendor-branches.sh`.

This paid off immediately. Static reading of the patch files predicted 26
overlapping files with 5 "HARD". The actual merge conflicted on 9 files / 10
hunks, and `navigator-toolbox.inc.xhtml`, `UpdateUtils.sys.mjs`, `browser.js`,
`findbar.js`, `ext-tabs.js` and `nsXREDirProvider.cpp` all merged without
conflict despite being flagged.

**Caveat that still stands:** a clean textual merge is not semantic
correctness. `navigator-toolbox.inc.xhtml` merging does not mean Glide's
toolbar markup renders correctly inside Zen's restructured sidebar.

### `rerere` with the cache outside `engine/`

`.rr-cache/` holds recorded conflict resolutions, symlinked to
`engine/.git/rr-cache`. It lives outside `engine/` because a Firefox version
bump does `rmtree engine`, which would otherwise discard every resolution.
`.rr-cache/` is intended to be committed.

Already proven: after the exclusion manifest was introduced, the vendor
branches were rebuilt from scratch and `CustomizableUI.sys.mjs` conflicted
again. rerere resolved it automatically with no prompting.

### Glide as a submodule, Zen as a remote

The first layout used sibling checkouts, `../glide` and `../zen-browser`. A
fresh clone could not recreate them: the Glide URL was not written down, the
synced commit lived in a separate `.glide-sync-base` file, and nothing checked
that the sibling matched it. A reclone on 2026-11-03 failed the build on
exactly that.

Glide is now the `vendor/glide` submodule. `.gitmodules` records the URL, the
gitlink records the commit, and a Glide update is one commit that moves the
gitlink together with the re-synced overlay and the regenerated patches, so the
pin and the generated files cannot drift apart. It sits outside `src/` because
surfer overlays everything under `src/` into `engine/`.

Zen cannot be a submodule because this repo is a Zen fork, so Zen upstream is
the `zen` remote, and `../zen-browser` is gone. Nothing read it.

`build-glide.sh` applies `glide-fixes/` to the submodule, so `.gitmodules` sets
`ignore = dirty` to keep that out of `git status`. A moved commit still shows.

The 3-way overlay recipe, `git diff <base> glide/main -- src/glide | git apply
-3`, is dropped. Every local change to Glide's files is carried in
`glide-fixes/`, so the overlay copy can safely overwrite, and conflicts surface
when the fixes are applied to the new Glide, inside the submodule where git has
the blobs for a real 3-way apply. The recipe would also have failed from this
repo: the preimages of the two fixed files were never committed here.

### Stay on Firefox 156.0.1

Glide targets 157.0b2, Zen 156.0.1. Applying Glide's 99 patches to pristine
156.0.1 gave **95 clean, 2 fuzzy, 2 failed**. The version delta costs
essentially nothing, so there is no reason to rebase Glide or wait for Zen's
157 sync.

- Failed: `search-config-v2.json`, `EventUtils.js`. Both in excluded groups.
- Fuzzy: `browser-menubar.inc.xhtml` (cosmetic) and
  `DesktopActorRegistry.sys.mjs` (**essential** — the actor registration behind
  keydown interception). The latter should get a clean re-export against 156.

### Move to Firefox 159.0.1 with Glide 0.1.65a

Superseded the 156 pin on 2026-11-07, in the first run of the scripted sync.
Zen `dev` had moved to 159.0.1, and Glide 0.1.65a targets 159.0b4, so the two
now sit on the same Firefox release. On pristine 159.0.1 all 273 of Zen's
patches and all 51 active Glide patches applied cleanly, with no fuzz, so the
`DesktopActorRegistry.sys.mjs` re-export above is no longer needed. The engine
merge hit one conflict, `CustomizableUI.sys.mjs`, which rerere replayed, and
`enso-glide-fixes.patch` applied unchanged.

---

## What is excluded, and why

Group membership: `scripts/enso/glide-patch-groups.tsv`.
Toggles: `scripts/enso/glide-excluded-groups.txt`.

`vendor-branches.sh` hard-fails if a Glide patch target is missing from the
TSV, so a new upstream patch cannot silently enter the build unclassified.

### `branding` — excluded

Glide's identity patches **merged cleanly, which was the wrong outcome.** They
did not conflict precisely because Zen does not patch most of those files, so
keeping them produced a browser writing to a `Glide Browser` profile directory,
announcing itself over DBus as `app.glide_browser`, and spoofing Glide in the
UA. This group also carries `GLIDE_FIREFOX_VERSION`, which duplicates Zen's
`ZEN_FIREFOX_VERSION` across six files — excluding the group collapses all of
those at once.

### `demozilla`, `testing`, `typecheck`, `sdk-pin` — excluded

- **demozilla**: betterfox/telemetry-stripping prefs. Zen declares prefs as
  YAML under `prefs/` compiled by `tools/ffprefs`; Glide's would fight it.
- **testing**: Glide's ~15.8k lines of mochitests assert against stock Firefox
  chrome and would fail wholesale against Zen's UI. Re-enable after triage.
- **typecheck**: JSDoc widening and vendored `.d.ts` to satisfy Glide's `tsc`
  run over Firefox sources. We do not run that check.
- **sdk-pin**: Glide pins macOS SDK 26.0. devenv supplies apple-sdk **26.5**,
  which is also what Zen's release mozconfig scans for.

### `gemini` — **kept**, despite the original plan to drop it

The Gemini protocol handler was going to be dropped as an unrelated feature.
It is kept because `DesktopActorRegistry.sys.mjs` registers `GeminiProtocol` in
the same patch as the three Glide actors, and `browser/components/moz.build`
adds the `gemini` DIR alongside other essential wiring. Excluding it means
hand-editing two essential patches, creating permanent divergence from upstream
Glide and breaking the sync-by-diff workflow. Carrying ~490 lines of
self-contained protocol handler is the cheaper trade.

### `caret` — **kept**, with two escape hatches

Keeping the vim block/underline caret (4 C++ patches, ~400 lines).

- **Runtime**: `glide.vimcaret=false`. Already exists upstream and gates every
  C++ call site (3 in `nsCaret.cpp`, 1 in `nsIFrame.cpp`). No rebuild needed.
  `glide.caret.style` takes `0` Block, `1` Underline, `2` Line, and is set from
  the current mode by `browser.mts:1421`.
- **Build-time**: uncomment `caret` in `glide-excluded-groups.txt`. Degrades
  gracefully — `browser.mts` still sets the pref, nothing reads it, the caret
  renders as a normal line.

`nsCaret.cpp` is the single most volatile patch in the set and should be
expected to break first on a Firefox bump.

---

## Mode indicator: colour signal + sidebar chip

Glide ships two toolbar buttons. Only the mode indicator is wanted.

- **`glide-toolbar-mode-button`** — keep, but re-home into Zen's sidebar via
  `ZenCustomizableUI` / `zen-sidebar-icons.inc.xhtml`, **not**
  `navbarPlacements`. Zen's compact mode hides the toolbar entirely and
  `_hasSetSingleToolbar` relocates nav-bar widgets, so a nav-bar button can
  vanish exactly when you most need to know you are in `insert`.
- **`glide-toolbar-keyseq-button`** — drop. Glide's `which-key` plugin covers
  pending-key display better.

The more durable half is the colour signal: `#update_mode_ui()` sets
`--glide-current-mode-color` on `:root` independently of any widget, so Zen
chrome (urlbar border, sidebar edge) can be tinted by mode with no toolbar
involvement. Palette: normal `#a89984`, insert `#83a598`, visual `#fe8019`,
command `#fb4934`, hint `#f3a`, op-pending `#b8bb26`, ignore `#cc79a7`.

Because the chip goes in the sidebar, **neither button belongs in
`navbarPlacements`** — which is why all 9 merge conflicts resolved uniformly to
Zen's side.

**Not yet done.** ⚠️ `navigator-toolbox-js.patch` still contains
`glide_keyseq_button.removeChild(...)` with no null guard. Once the keyseq
button is removed from the markup, that line throws inside `DOMContentLoaded`
and takes out every handler registered after it.

---

## Toolchain

devenv (`devenv.nix`) ports Glide's `flake.nix`, which is a known-good
Firefox-on-Nix-darwin environment. Three deliberate deviations:

1. **`MOZ_OBJDIR` dropped.** Glide forces `engine/objdir`; surfer locates the
   object directory by globbing `engine/obj-*` and has no `MOZ_OBJDIR`
   awareness, so keeping it would break `surfer package`.
2. **Configure flags go to an untracked root `./mozconfig`**, which surfer
   concatenates third (after `configs/common` and `configs/<os>`, before its
   internal block). `mozconfig` was already in Zen's `.gitignore`.
3. **npm/node 22 and python 3.11** per Zen's `.nvmrc` and `.python-version`,
   rather than Glide's pnpm/node 24. Plus a `gtar` alias derivation, because
   surfer invokes `gtar` by name on macOS and nixpkgs `gnutar` only ships
   `tar`.

The whole environment realises from `cache.nixos.org` — no LLVM rebuild.
`stdenv` is overridden to clang 21.1.8 (rustc's LLVM) so cross-language LTO
works.

Known deltas to watch on first build:

- A stray `apple-sdk-14.4` sits in the closure alongside 26.5. Configure prints
  the SDK it selects, so a wrong pick will be loud.
- rustc is 1.98.1 vs Zen's `.rust-toolchain` 1.95.0. Pinning exactly would mean
  sourcing rust from fenix/rust-overlay, which breaks the
  `pkgs.rustc.llvmPackages` coupling the LTO setup depends on.

---

## The path must stay ASCII

The parent directory was `ensō`. The Nix clang wrapper mangles non-ASCII paths:
`ō` is UTF-8 `0xC5 0x8D` = octal `\305\215`, and the linker received
`$/Users/.../ens305215/enso/...` — bash ANSI-C quoting (`$'\305\215'`) leaking
through unexpanded. Every Rust component failed to link, starting with
`tools/ffprefs` and certain to include Firefox's own crates.

Confirmed by controlled test: the identical crate builds in 5s at
`/tmp/enso-ascii-test` and fails at the `ensō` path. Locale was already
`en_US.UTF-8`, so this is not a locale problem.

Renamed to `/Users/jamie/Developer/Sources/enso`. **Do not reintroduce
non-ASCII characters anywhere in the build path.** The project can still be
called Ensō; only the filesystem path is constrained.

`.rr-cache` survived the move because its symlink is relative. Surfer's overlay
symlinks did not — it writes absolute targets, so all 335 are dangling until
`npm run import` recreates them.

---

## Symlink vs content process: resolved, and it fails

Glide copies `src/glide` into `engine/` rather than symlinking. The reason,
from `scripts/copy-src.mts`, is that content processes "cannot access anything
outside of the `engine/` directory". That is literally true on macOS, and the
mechanism is now traced:

1. `engine/toolkit/moz.configure:1059` sets `MOZ_JAR_MAKER_FILE_FORMAT=symlink`
   on everything except Windows, so `jar.py:517` symlinks into
   `objdir/dist/bin/chrome/` instead of copying. `FINAL_TARGET_FILES` (how the
   actors ship) uses `AbsoluteSymlinkFile` likewise. The build does **not**
   dereference into real copies.
2. `ContentParent.cpp:2396-2420` whitelists only the repo dir (`engine/`, read
   from Info.plist `MozillaDeveloperRepoPath`) and the objdir for
   content-process reads. `SandboxPolicyContent.h:65` allows
   `file-read-metadata` everywhere — so symlinks *resolve* — but
   `file-read-data` is evaluated against the **resolved final path**. There is
   no `MOZ_DEVELOPER_REPO_DIR` escape hatch on macOS; that exists only for
   Linux and Windows.

Zen never hit this because it ships no content-process JS through its overlay.
`GlideHandlerChild.sys.mjs` is exactly that, so we do.

Scope: packaged builds pack into `omni.ja` and are unaffected. This breaks
**dev builds only** — i.e. the entire inner loop.

**Fix:** graft Glide's `scripts/copy-src.mts`, and patch surfer's
`copy-patches.js:45` so paths under the glide tree take the `copyFile` branch
that already exists at line 41 for Windows, rather than `ensureSymlink`.
Non-glide `src/` files stay symlinked — they are read by the unsandboxed parent
process. The remaining objdir symlink hop is fine because it points *into*
`engine/`, which is whitelisted.

Cheap pre-build check:
`readlink -f engine/glide/browser/base/content/dist/browser-hints.mjs` — if it
resolves outside `engine/`, content reads will be denied. At runtime, set
`security.sandbox.logging.enabled=true` and watch for `deny file-read-data`.

---

## Keyboard architecture: Glide wins dispatch, bridge the rest

Glide's capture-phase listener **deterministically beats** both keysets, so
coexistence already works mechanically. `XULKeySetGlobalKeyListener` executes
commands only on the system-group bubble pass (`GlobalKeyListener.cpp:171-194`;
`WalkHandlers` at `:90-107` returns immediately on `DefaultPrevented()`), while
Glide listens in default-group capture on the same document. Unmapped keys fall
through to XUL for free.

Two real hazards, neither an ordering race:

- `reserved="true"` keys (Zen re-emits these at `ZenKeyboardShortcuts.mjs:508`)
  get `MarkAsReservedByChrome()` during default-group capture, which stops the
  event ever reaching the content process — `GlideHandlerChild` goes blind.
- `zen.keyboard.shortcuts.disable-mainkeyset-clear` is **not** an off switch. It
  only skips clearing `#mainKeyset` while still populating `#zenKeyset`,
  producing double-firing.

The real mode lever is `#zenKeyset[disabled]`: `GlobalKeyListener.cpp:623-627`
checks the `disabled` attribute before executing, so `setAttribute("disabled",
"true")` neuters the keyset atomically with no DOM teardown.

Single source of truth: keep Zen's `_currentShortcutList` authoritative (it is
persisted, migrated and user-editable) and project it into Glide keymaps from a
new Zen-side `src/zen/kbs/ZenGlideKeymapBridge.mjs`, binding through
`document.getElementById(action).doCommand()` so the existing dispatch path is
reused. Bridge only modified-key shortcuts; bare keys stay Glide's.

`ZenGlance` vs `GlideHandler` is not actually a contention — Glance only reacts
to unprevented Escape. It loses because Glide's `stopImmediatePropagation()`
(`browser.mts:1750`) stops the event reaching the content process at all, so
Escape dismisses Glance in `normal` mode only. Fix by moving Glance's Escape
handling to the parent (state already lives there, `ZenGlanceManager.mjs:264`)
and owning `<Esc>` in the bridge with a Glance-first chain.

Every integration point is a public Glide API or a Zen file.

---

## Excmd UI: keep both surfaces

The two are **not** the same interaction and should not be collapsed. Glide's
`:` is a mode taking typed positional arguments (`:set scroll_step 100`,
`:tab 3`); Zen's palette is a zero-argument fuzzy list in the urlbar. Routing
`:` into the urlbar would hand focus to `gURLBar` and break mode dispatch, the
command-mode caret, and `CommandLineExit` autocmds. `GlideCompletionSource` is
also public config API, so removing it is a breaking change for users.

Decision: keep `:` for modal/argument use **and** expose zero-argument excmds as
urlbar palette results — one action pool, two surfaces.

- Adapter tree at `src/enso/`, mirroring how `src/zen/` sits beside
  `src/browser/`.
- Filter excmds to those with no required args; reuse each command's existing
  `description` as the label rather than inventing 100+ FTL strings.
- `ZenUrlbarProviderGlobalActions` keeps `#getAvailableActions` private, so
  subclassing cannot extend the pool. Minimal change is ~4 lines in
  `ZenUBGlobalActions.sys.mjs` adding an `extraSources` registry — permitted,
  since the discipline rule covers `src/glide/`, not `src/zen/`.
- `ZenUBResultsLearner` is keyed on command id and registry-agnostic, so excmds
  get usage-learned ranking for free.
- Visual unification is token remapping: Glide's commandline exposes ~30
  `--glide-cmdl-*` / `--glide-cmplt-*` custom properties, so a Zen-side
  stylesheet can rebind them to `zen-omnibox.css` tokens without rewriting
  `glide-commandline.ts`.
- Reverse bridge: iterate `globalActions` calling `glide.excmds.create()`, which
  yields `:zen_compact_mode_toggle` etc. with Zen's own localized labels.
  Driving off `globalActions` rather than parsing the commandset XHTML also
  picks up icons, l10n and function-commands in one pass.

---

## Mode indicator: concrete plan

- **Chip** goes in `zen-sidebar-foot-buttons`: add markup to
  `src/browser/base/content/zen-sidebar-icons.inc.xhtml` and append the id to
  `defaultSidebarIcons` in `ZenCustomizableUI.sys.mjs:16-22`. That array is both
  the `defaultPlacements` and the removable-forcing loop, so one edit covers
  registration.
- Use `<toolbaritem>` wrapping an explicit `<html:span>`, **not**
  `<toolbarbutton>`. That eliminates the anonymous icon child the `removeChild`
  hack existed to strip.
- **Tint target is `#zen-main-app-wrapper`.** Everything else dies: the sidebar
  splitter is `display:none` in compact mode, `#navigator-toolbox` slides
  offscreen (`sidebar.inc.css:52-100`), and the urlbar is `opacity:0` and moves
  into the sidebar under `_hasSetSingleToolbar`. Add a second inset `box-shadow`
  stroke on `.browserSidebarContainer` to cover `:root[zen-no-padding="true"]`,
  where the gutter collapses to zero.
- `:root` custom properties **do** reach the sidebar: `glide.styles.add()`
  appends to the chrome document's `<head>`, and Zen's sidebar nodes are plain
  markup in the same document with no shadow boundary.
- Hazard: `browser-api.mts:971` registers injected style elements in
  `reload_config_remove_elements`, so a config reload drops the mode colour
  until the next mode change. Re-trigger the mode UI update from the Zen-side
  adapter on reload rather than editing `browser-api.mts`.
- **One forced `src/glide/` violation**, kept to a single line.
  `browser.mts:1488` hard-codes `element.childNodes[0]`; change it to
  `(document.getElementById("glide-toolbar-mode-label") ?? element.childNodes[0])`,
  which stays backwards-compatible with upstream Glide markup and so rebases as
  a trivial conflict. `dist/browser.mjs` is generated — regenerate, never
  hand-edit.

---

## Build fixes found by actually building

Four real defects, in the order they surfaced.

### `firefox.js` is generator-owned, so it cannot be patched

`npm run import` runs `tools/ffprefs` (Rust) *before* surfer applies patches,
and `prepare_zen_prefs()` appends `#include zen.js` to
`engine/browser/app/profile/firefox.js`. Glide's patch against the pristine
file therefore never matches. Zen already knows this — `firefox.js` is in the
`IGNORE_FILES` list in `scripts/recalculate-patches.sh`.

Fix: moved `browser/app/profile/firefox.js` into a new `generator-managed`
excluded group, deleted the exported patch, and taught `ffprefs` to emit
`#include glide.js` alongside `#include zen.js`. Net one fewer patch to carry.

### Overlay sync skipped symlinks

`sync-glide-overlay.sh` used `find -type f`, which silently skips symlinks.
Glide's `src/browser/actors/` is *seven relative symlinks* into
`../../glide/browser/actors/dist/`. They were never copied, so
`browser/actors/moz.build` registered actors whose files did not exist and the
build died with a `SandboxValidationError`. Fixed with
`find \( -type f -o -type l \)` and `cp -Pp`. Dereferencing would have been
wrong too: it snapshots stale build output instead of tracking `dist/`.

### RLBox wasm sandboxing disabled

Configure rejected the Nix wasi sysroot: "Cannot find wasi libraries or problem
with the wasm linker". The sysroot links only `libcxx`, because Glide's flake
relies on its compiler wrapper to supply wasi libc and crt. Set
`wasmSandbox = false` in `devenv.nix`, which swaps `--with-wasi-sysroot` for
`--without-wasm-sandboxed-libraries`. **The two are mutually exclusive** —
passing both fails with "--with-wasi-sysroot is not available in this
configuration". This drops sandboxing for graphite/ogg/hunspell, which is real
hardening, so fix the sysroot before shipping a release build.

### Tutor dist is a separate build step

`glide.jar` references `browser/components/tutor/dist/index.html`, which
`build:ts` does not produce — it comes from `scripts/build-docs.mts`. The build
compiled for 46 minutes and then died in jar packaging. **Glide needs three
build steps before a sync, not two:** `pnpm build:ts`, `pnpm bundle`, and
`pnpm build:docs:html`, all run in the Glide checkout. `build-glide.sh` now runs
all three.

### Materialize skipped generated files and symlinks

Two gaps in `materialize-overlay.sh`, found after the 2026-11-03 reclone.

- Surfer links `src/` into `engine/` only during import, so anything generated
  later, such as Glide's build output after a rebuild, has no `engine/`
  counterpart. The script skipped those on the assumption that they were not
  part of the build. Surfer overlays every non-patch file in `src/`, so the
  script now adds them itself, with the `engine/.gitignore` entry surfer would
  have written.
- It used `find -type f`, the same mistake the overlay sync made, and so never
  saw Glide's actor symlinks in `src/browser/actors/`. Their `engine/` links
  resolve outside `engine/`, which the content sandbox denies. It now copies
  them dereferenced.

### Surfer's import is not idempotent

Re-running `npm run import` over an already-patched tree fails on
`src/external-patches/firefox/issue_14710.patch` (Picture-in-Picture, a Zen
patch). Surfer does `git apply -R` with errors swallowed, then `git apply`; for
a multi-file patch where the revert partially fails, the re-apply then fails.
The tree content is still correct, so this is noise rather than corruption —
but it means import cannot be used to "top up" an existing tree. Either reset
to base first, or skip import and call mach directly.

### mach hides build errors from coding agents

`build_commands.py:217` calls `is_running_under_coding_agent()` and forces
`quiet = True`, printing "AI agent detected. Terminal output limited to
warnings and errors." Two separate build failures showed only "*** Fix above
errors" with the actual cause suppressed. `--verbose` overrides it, but surfer
invokes `mach build` with no flags, so diagnosing means bypassing surfer:

```bash
cd engine && ./mach build --verbose
```

Surfer's only contribution to `build` is writing `engine/mozconfig`, so calling
mach directly is safe once a build has been configured once.

---

## Open items

- **`git clean` permission.** `vendor-branches.sh` now runs `git clean -fdq`
  after `reset --hard`, because a handful of patches on both sides create new
  files that `reset` leaves behind, causing "would create the file, which
  already exists" on re-runs. The permission classifier blocked running the
  script with that line, so **the fix is committed but unexercised**. Without
  it, two of Zen's patches
  (`test_write_json_length_hint.js`, `test_subprocess_pipe_flags.js`, both
  xpcshell tests) fail on the second and later runs. The current `enso` branch
  was built with those two missing.

  Consequence of the ordering: `vendor-branches.sh` must run **before**
  `npm run import`, never after, or `clean -fd` removes the overlay symlinks.

- **`glide.js` pref chain.** The essential `firefox.js` patch does
  `#include glide.js`, and `glide.js` in turn includes `remove-mozilla.js` and
  `betterfox.js`. All three were copied to keep zero divergence from upstream
  Glide, which means betterfox's opinionated prefs are in the build even though
  the `demozilla` *patch* group is excluded. Audit these against Zen's prefs;
  if they conflict, the clean fix is to drop the `firefox.js` patch and add
  `#include glide.js` through Zen's own `prefs/` pipeline instead of editing
  `glide.js`.

---

## Sync workflow

The commands are in [ENSO.md](ENSO.md#updating). This section records why they
have the shape they do.

### Zen's history stays out of this repo

Zen rewrote its `dev` history after this fork was cut. The fork's base,
`968d6a905`, has the same tree as Zen's `7dfcd34fc` under a different hash,
and the two histories share nothing after April 2024. The rewritten history
also carries signed Windows builds of about 95 MB each, committed in September
2024 and deleted a month later, which this fork's copy never had. Reconnecting
the two with a `-s ours` merge was tried first, and it made the next push about
5.7 GB, over GitHub's 2 GB limit.

So Zen's commits never enter this repo's history. `.zen-sync-base` records the
last Zen commit synced, and `sync-zen.sh` squash-merges from there to
`zen/dev`. A temporary local `git replace --graft` gives HEAD that commit as a
second parent, so git takes it as the merge base and the full merge machinery,
rename detection and rerere included, still applies. The graft is deleted
straight after the merge and is never pushed. Each Zen sync is one commit here,
and its message lists the Zen commits it squashes.

If Zen rewrites again, `sync-zen.sh` stops because `zen/dev` no longer contains
the recorded commit. It prints the command that finds the commit with the same
tree; record that one and re-run.

### The repo-level merge is mechanical

`src/**/*.patch` is generated: `export-patches.sh` resets every patch to Zen's
own and then writes the merge result over the files Glide touches. So
`sync-zen.sh` resolves every patch conflict to Zen's side, and the real
integration happens in `engine/`, where conflicts are on real source and
rerere replays known resolutions. The sync stays uncommitted until
`integrate.sh` has regenerated the patches, so the sync commit itself builds.

### `vendor/zen` comes from the zen remote

`vendor-branches.sh` used to build `vendor/zen` from this repo's `src/`. After
the first export those patches already contain Glide, so `vendor/zen` would
have been Zen plus Glide, and the merge would have been Glide into itself. It
now extracts Zen's `src/` with `git archive` at the commit recorded in
`.zen-sync-base`.

### Resetting `engine/`

- `surfer download` does nothing when `engine/` exists, whatever its version.
  `integrate.sh` deletes `engine/` when its root branch, which surfer names
  after the Firefox version, does not match `surfer.json`.
- Surfer's import does not reset first, and `vendor-branches.sh` leaves
  `engine/` on the `enso` branch with every patch committed, so import would
  apply them twice. `integrate.sh` switches back to the pristine root first.
- A fresh `engine/.git` has its own empty rr-cache, so `vendor-branches.sh`
  replaces it with a link to `.rr-cache/`.

### Discipline rule

Never edit a file under `src/glide/` in place, because `sync-glide-overlay.sh`
overwrites it. Prefer an adapter alongside that Zen-specific code calls into.
When Glide's own code has to change, put the change in
`scripts/enso/glide-fixes/`, which `build-glide.sh` applies to the submodule
before building. Code that is simply dead under Zen, such as the ~200 lines of
CSS hacks against `#TabsToolbar` in `utils/browser-ui.mts`, can be deleted the
same way.
