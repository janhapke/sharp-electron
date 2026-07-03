# sharp-electron

A drop-in replacement for [`sharp`](https://github.com/lovell/sharp) that doesn't segfault under Electron on Linux.

`sharp` crashes with a native segfault — not a catchable JS error — when decoding an image (JPEG, PNG, etc.) inside any process built on Electron's Linux binary. The cause is two copies of `glib` colliding in one process; no configuration flag fixes it. This package is a rebuild of `sharp` and its bundled `libvips` with the collision fixed at the linker level. To use it, add one `overrides` entry to your `package.json` ([Usage](#usage)). macOS and Windows aren't affected, so there this package transparently re-exports the real, unmodified `sharp`. To rebuild it yourself or bump it to a newer `sharp` release, see [Building from source](#building-from-source) and [Engineering notes](#engineering-notes).

## The problem

Electron's Linux binary dynamically links the system's `glib` (for GTK integration). `sharp`/`libvips` bundle their own private `glib` inside `libvips-cpp.so`, but don't fully hide its symbols. Two copies of `glib` exporting the same symbols into one process corrupt `glib`'s internal state, and the process dies with `SIGSEGV` the first time an image is actually decoded — no JS exception, no stack trace. This affects any process built on Electron's binary, including a `utilityProcess`, and is a known, currently-unresolved upstream bug: [electron/electron#46323](https://github.com/electron/electron/issues/46323).

Characteristically, *encoding* raw pixels works fine — only *decoding* a real compressed image crashes. If that matches what you're seeing, this is your bug.

## Usage

Use npm `overrides` — not a direct `import` — so that **every** `require('sharp')` / `import sharp from 'sharp'` in your dependency tree, direct or transitive, resolves to this package:

```json
{
  "overrides": {
    "sharp": "npm:@janhapke/sharp-electron@0.35.3-electron.0"
  }
}
```

```bash
npm install
```

That's it — no source changes anywhere in your project. The `npm:` alias syntax is required: the override target's package name differs from `sharp`, so a plain `"sharp": "0.35.3-electron.0"` would tell npm to look for a package literally named `sharp` at that version, which doesn't exist.

If `sharp` is also a **direct dependency** of your project, npm rejects an override that conflicts with it (`EOVERRIDE`). In that case point the dependency itself at this package and let the override reference it:

```json
{
  "dependencies": {
    "sharp": "npm:@janhapke/sharp-electron@0.35.3-electron.0"
  },
  "overrides": {
    "sharp": "$sharp"
  }
}
```

### Local testing against an unpublished build

To test a locally built copy of this repo (see [Building from source](#building-from-source)) instead of the published package:

```json
{
  "overrides": {
    "sharp": "file:../sharp-electron/package"
  }
}
```

After rebuilding this package, force a refresh in the consuming project — an `overrides`-resolved `file:` target gets **copied** into `node_modules/sharp`, not symlinked, so a plain `npm install` may not pick up the change:

```bash
rm -rf node_modules/sharp && npm install
```

### Why `overrides`, not a direct import

You *can* instead `npm install @janhapke/sharp-electron` and change call sites to import it directly — but only safely if you change **every** place your project touches `sharp`, including transitive dependencies you don't control.

The failure mode if you miss one: this package and the real `sharp` both ship a `libvips-cpp.so` with the identical SONAME (intentionally, for compatibility). The ELF dynamic linker deduplicates shared libraries by SONAME **within a process** — once one `libvips-cpp.so` is loaded, every other module in that process that needs that SONAME silently reuses the already-loaded copy, regardless of how correctly it was built or what its RPATH says. So if two plugins each import `sharp` and only one is switched over, whichever loads first wins for both. If the unpatched one wins, the symptom isn't even the original segfault — it's a confusing ELF loader error (`undefined symbol: vips_g_...`) in the correctly-patched module. This exact scenario happened while validating this package in a real project.

`overrides` sidesteps the problem structurally: every `sharp`-touching module resolves to the exact same files, so two different `libvips-cpp.so`s can never coexist in the process. Auditing call sites by hand gives no such guarantee.

### Platform support

| Platform | Behavior |
|---|---|
| `linux-x64` | The patched build. Verified against `sharp`'s own upstream test suite and a dedicated Electron crash-regression test. |
| `linux` (other architectures, e.g. `arm64`) | Throws a clear error at load time rather than silently falling back to real `sharp` — a silent fallback would just defer the crash to the first image decode. |
| macOS / Windows | Re-exports the real, unmodified `sharp` (a normal dependency of this package; npm installs the correct official binary automatically). The bug doesn't exist on these platforms. |

### Troubleshooting

- **`undefined symbol: vips_g_...` at load time** (an exception, not a crash) — almost always the SONAME-collision issue described above: some module in the process still resolves `sharp` to the real, unpatched package. Check that the `overrides` entry is in place and that `node_modules/sharp` actually contains this package's files.
- **Segfault decoding an image under Electron on Linux, even with `overrides` correctly in place** — an unpatched `libvips-cpp.so` from some other source is winning the SONAME race (e.g. a copy loaded by a non-npm mechanism). Check what else in the process loads `libvips`.

## Building from source

Requires only Docker on the host — the entire toolchain runs in a container matching `sharp`'s own CI environment.

```bash
git clone --recurse-submodules https://github.com/janhapke/sharp-electron.git
cd sharp-electron
npm install
npm run build
```

This applies the patches to the vendored `sharp-libvips`/`sharp` submodules, rebuilds both, runs both test gates, and packages the result into `package/` — ready to consume via a `file:` override as shown above. The individual stages are also available separately: `npm run build:libvips`, `npm run build:sharp`, `npm run test:gates`, `npm run package`.

To confirm the bug itself on the *unpatched* `sharp` first (recommended before trusting any of this): `npm run repro` runs [test/electron-crash-repro.js](test/electron-crash-repro.js) against the stock npm `sharp` under `ELECTRON_RUN_AS_NODE` — expect the encode step to succeed and the decode step to kill the process.

## Engineering notes

Everything a contributor (or future maintainer bumping versions) needs to know about how and why this works.

### How the fix works

The fix has two halves, applied as patches (in [patches/](patches/)) to two upstream repos vendored as git submodules pinned at release tags. The submodules stay pristine in git; [scripts/apply-patches.sh](scripts/apply-patches.sh) applies the patches to their working trees at build time (idempotently — it detects an already-patched tree and skips).

**Phase A — `sharp-libvips` (the `libvips` binary).** `sharp-libvips` doesn't vendor `libvips`'s source; its `build/posix.sh` downloads the upstream release tarball at build time and patches it inline. Our patch extends that same mechanism:

- Adds `extra/glib_wrapper.c`/`.h`: thin wrapper functions re-exporting each needed `glib` symbol under a renamed `vips_g_*` identity (e.g. `vips_g_malloc` calls the bundled `glib`'s `g_malloc`).
- Broadens the `vips.map` linker version script from hiding a single symbol (`g_param_spec_types` — upstream's own partial fix for this class of bug) to hiding *everything* except `libvips`'s own API: `{ global: vips_*; _Z*; local: *; }`. This is what actually removes the colliding `g_*` exports from `libvips-cpp.so`.
- Patches `libvips`'s C++ header `VImage8.h`, whose inline `VObject` smart-pointer class calls `g_object_ref`/`g_object_unref` directly — those calls get compiled straight into `sharp`'s addon wherever `vips::VImage` is used, so they must be redirected at the header level, not in `sharp`'s source.

One non-obvious gotcha, recorded because it *will* bite again: `libvips-cpp.so`'s meson target sets `gnu_symbol_visibility: 'hidden'`, which strips any new symbol from the dynamic table at compile time — before the version script even applies — unless it's explicitly marked `__attribute__((visibility("default")))`. The build succeeds cleanly either way; only `objdump -T` reveals the difference. A clean build is not sufficient evidence here.

**Phase B — `sharp` (the Node addon).** Redirects `sharp`'s own direct `glib` calls (`common.cc`, `metadata.cc`, `sharp.cc`) to the `vips_g_*` wrappers, then rebuilds the addon against the Phase A `libvips` using `sharp`'s own supported mechanism for custom libvips builds: `SHARP_FORCE_GLOBAL_LIBVIPS=1` plus `PKG_CONFIG_PATH` pointed at generated `.pc` files. The build runs in a Docker image ([scripts/sharp-build.Dockerfile](scripts/sharp-build.Dockerfile)) replicating `sharp`'s official CI environment (Rocky Linux 8, gcc-toolset-14, Node 20), so nothing touches the host toolchain and the binary matches upstream's baseline glibc compatibility.

### The wrapper symbol set

Seven symbols are wrapped. The machine-readable source of truth — including each symbol's origin, risk classification, and how it was found — is [patches/wrapper-symbols.json](patches/wrapper-symbols.json); version bumps should diff a fresh grep against that file, not against this prose. The short version:

- `g_object_ref`, `g_object_unref` — from `libvips`'s `VImage8.h` inline header (see Phase A above); the original crash culprits.
- `g_malloc`, `g_free` — from `sharp`'s own source. Wrapped **as a pair** deliberately: an allocator and its matching free must come from the same `glib` copy, or the result is silent heap corruption, not just a symbol-hygiene issue.
- `g_signal_connect_data`, `g_log_set_handler` — from `sharp`'s own source.
- `g_utf8_validate` — from `sharp`'s `metadata.cc`. Notably, this one was **missed by grepping** and only surfaced when running `sharp`'s full test suite against the rebuilt addon (`undefined symbol` at runtime). Lesson: the test-gate loop below is load-bearing, not a formality — expect a version bump to surface a symbol the grep missed.

### Packaging details that matter

Three hard-won, non-obvious decisions live in [scripts/package-local.sh](scripts/package-local.sh):

- **`libvips-cpp.so` sits next to the `.node` addon, found via RPATH — and it must be old-style `DT_RPATH`, not `DT_RUNPATH`.** `patchelf --set-rpath` produces `DT_RUNPATH` by default, which the loader consults *after* `LD_LIBRARY_PATH` — so anything else in a real consumer's environment or `node_modules` that provides the same SONAME can win over the co-located patched copy. `patchelf --force-rpath` produces `DT_RPATH`, consulted *before* `LD_LIBRARY_PATH`, so the co-located copy always wins for the addon's own direct dependency. (Setting `process.env.LD_LIBRARY_PATH` from JavaScript doesn't work at all: glibc reads it once at process start, not per `dlopen()`.)
- **The SONAME is kept identical to upstream's** — that's what makes the per-process SONAME deduplication safe *when everything resolves to this package* (see [Why overrides](#why-overrides-not-a-direct-import)) and is why `overrides` is the recommended install method rather than an optional nicety.
- **`package/` runs its own `npm install` during packaging** because npm does not recursively install a `file:` dependency's own dependencies the way it does for registry packages — without this, the non-Linux `require('sharp')` fallback breaks in every local-testing setup. Relatedly, `package/package.json` must **not** declare `"os"`/`"cpu"` restrictions: those make npm skip installing the package entirely on other platforms, which would prevent the fallback from ever existing there.

### Test gates

Every build must pass both, enforced by [scripts/run-gates.sh](scripts/run-gates.sh) (non-zero exit on failure, usable in CI):

1. **`sharp`'s own upstream test suite** against the rebuilt addon (1804/1811 at last run; the one known failure is `test/unit/esm.mjs`, a pre-existing Node CJS/ESM interop quirk unrelated to these patches — it fails identically against stock `sharp`).
2. **The Electron crash regression test** ([test/electron-crash-repro.js](test/electron-crash-repro.js)): encode raw pixels to JPEG, then decode a real JPEG via `.metadata()` and `.resize().toBuffer()`, under `ELECTRON_RUN_AS_NODE`. On an unpatched build the decode step reliably segfaults; on a correct build both steps pass. The same script serves both directions via `SHARP_MODULE_PATH`.

**If a gate fails with `undefined symbol: g_<something>`**: that's a missing wrapper symbol. Add it to `extra/glib_wrapper.c`/`.h` in `vendor/sharp-libvips` (remember the `visibility("default")` attribute), patch the call site, update `patches/wrapper-symbols.json`, regenerate the patch files, rebuild, re-run the gates. This loop is normal — it's how `g_utf8_validate` was found.

### Alternatives that didn't work

Tried before concluding a from-source rebuild was the only real fix:

| Approach | Result |
|---|---|
| `LD_PRELOAD` sharp's `libvips-cpp.so` before Electron starts | Made Electron crash even earlier |
| `objcopy --localize-symbols` (hide symbols post-hoc, no recompile) | Still segfaults — `sharp.node`'s undefined references then bind to Electron's `glib` instead |
| `RTLD_DEEPBIND` | Crashes differently, during load |
| Do `sharp` work in a real separate Node process (not Electron's binary) | Works, but requires bundling a Node binary and adds an IPC boundary |

### Updating to a new `sharp` release

This is deliberately a guided Claude Code command, not a blind script: [.claude/commands/rebuild-for-version.md](.claude/commands/rebuild-for-version.md) (`/rebuild-for-version <sharp-version> <sharp-libvips-version>`). A version bump involves genuine judgment calls a script would get silently wrong — whether the bug even still reproduces upstream, whether a patch conflict is trivial context drift or a structural change, whether the wrapper symbol set changed. The command:

1. Re-pins the submodules and first verifies the bug **still reproduces on an unpatched build** — upstream may have fixed it.
2. Attempts the existing patches; diagnoses (rather than force-fixes) any conflict.
3. Re-runs the exhaustive `glib`-call grep and diffs it against `patches/wrapper-symbols.json`.
4. Rebuilds, runs both gates, and follows the wrapper-expansion loop above (bounded to 3 iterations before stopping to report).
5. Re-verifies symbol visibility (`objdump -T`) and `DT_RPATH` (`readelf -d`), and prepares — **but never executes** — the release.

Version scheme: `<upstream-sharp-version>-electron.N` — the version always names the exact `sharp` release it tracks; `N` bumps for this package's own revisions. Every version this scheme produces is, by construction, a semver **prerelease** (the `-electron.N` suffix), which matters at publish time — see below.

### Releasing

`npm run release <version>` ([scripts/release.sh](scripts/release.sh)) runs the full pipeline, then syncs every version reference — `package/package.json`'s `version` and its `sharp` fallback dependency (pinned to the upstream part of the new version), and this README's install snippets — then prints the remaining steps. **Publishing is always a manual, human-confirmed action** — no script or command in this repo runs `npm publish`, `git tag`, or `git push` on its own. That's a deliberate design decision, not a missing feature: a bad automated judgment call shipping silently to consumers is a worse failure mode than a release waiting a day for review.

**Publishing requires `--tag latest`, every time**: `npm publish --tag latest` (not plain `npm publish`). Because every version has the `-electron.N` suffix, npm/semver treats it as a prerelease and refuses to move the `latest` dist-tag implicitly (`npm error: You must specify a tag using --tag when publishing a prerelease version`) — without `--tag latest`, a bare `npm install @janhapke/sharp-electron` (or the version-less `overrides` form) would resolve to nothing. `--access public` is not needed on the command line; it's already set via `package/package.json`'s `publishConfig`.

Note for the published package: `package/README.md` is generated at package time (a copy of this file, since npmjs.com displays the published package's own README) — edit this file, never that copy.

### Repository layout

```
patches/                     the actual fix: two .patch files + wrapper-symbols.json (symbol manifest)
vendor/sharp-libvips/        git submodule, pinned at the target release tag (pristine; patched at build time)
vendor/sharp/                git submodule, same
scripts/                     the full pipeline: apply-patches → build-libvips → build-sharp → run-gates → package-local
test/electron-crash-repro.js the regression test (and original bug repro)
package/                     the published npm package: index.js dispatcher, index.d.ts (forwards to sharp's own types), built linux-x64/ payload
dist/                        gitignored Phase A build output
.github/workflows/ci.yml    Linux full-pipeline job + macOS/Windows fallback smoke test
```

## Status

The `linux-x64` build passes both test gates and has been verified end-to-end in a real consuming Electron project. The macOS/Windows fallback is implemented and covered by CI — check the [workflow's status](.github/workflows/ci.yml) for the current result on real runners. `linux-arm64` has no patched build — it fails loudly rather than silently.

## License

Apache-2.0, matching `sharp`. See [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) (this project patches `libvips`, LGPL-2.1-or-later; the `glib_wrapper.c`/`.h` shim is original code).
