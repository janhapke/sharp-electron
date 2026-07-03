---
description: Re-run this project's patch/build/test pipeline against a new sharp/sharp-libvips release, with judgment at each step rather than blind reapplication.
argument-hint: <sharp-version> <sharp-libvips-version>
---

# Rebuild for a new `sharp`/`sharp-libvips` version

Arguments: `$ARGUMENTS` — expected as `<sharp-version> <sharp-libvips-version>`, e.g. `0.36.0 1.4.0`. If either is missing, ask for it before doing anything else.

This is **not** a script to run to completion unattended — it's a guided process with real judgment calls at several points. Read all of this before starting, and stop to report back (rather than guessing and continuing) at any point marked **STOP**. The design rationale for why this is a command and not a shell script is in `README.md`'s "Updating to a new `sharp` release" section — read that first if this is the first time running this command.

## Step 0: Orient

- Read `patches/wrapper-symbols.json` — the current source of truth for which symbols are wrapped and why.
- Read `README.md`'s "Engineering notes" section (especially "How the fix works" and "The wrapper symbol set") for the full context of what was done for the *current* target version and why.
- Confirm the new target versions are real releases: check `https://github.com/lovell/sharp/releases` and `https://github.com/lovell/sharp-libvips/releases` (or the npm registry) for the tags given in `$ARGUMENTS`.

## Step 1: Check whether the bug still reproduces at all — before assuming any patches are needed

Do not skip this by assuming "same bug, same fix." Upstream could have partially or fully fixed this independently since the current target version.

1. Update the submodule pins: `git -C vendor/sharp-libvips fetch --tags && git -C vendor/sharp-libvips checkout v<sharp-libvips-version>`, same for `vendor/sharp`.
2. Build **unpatched** — do *not* run `scripts/apply-patches.sh` yet. Just run `sharp-libvips`'s own `build.sh linux-x64` and `sharp`'s own default build (against the npm `@img/sharp-libvips-linux-x64` package, not `SHARP_FORCE_GLOBAL_LIBVIPS`) to get a genuinely stock addon.
3. Run `test/electron-crash-repro.js` (with `SHARP_MODULE_PATH` pointed at this stock, unpatched `vendor/sharp`) via `ELECTRON_RUN_AS_NODE=1 electron ...`.
4. **STOP and report** if it does *not* crash. Investigate why before proceeding — check `sharp-libvips`'s `build/posix.sh` for whether they broadened their own `vips.map` fix, check the [Electron tracking issue](https://github.com/electron/electron/issues/46323) for whether it's been closed, check whether `libvips`'s `VImage8.h` still has the same inline-header pattern. The patches in this repo might need to shrink, change shape entirely, or (best case) not be needed at all for this version. Do not proceed with the rest of this process on autopilot if this happens — the right next step depends entirely on *why* it's fixed.

If it still crashes (expected, most likely outcome): continue to Step 2.

## Step 2: Attempt to apply the existing patches

1. Run `scripts/apply-patches.sh`.
2. **Clean apply**: proceed to Step 3.
3. **Apply failure**: diagnose *why*, don't just retry blindly.
   - Pull up the specific hunk that failed. Diff the relevant upstream file between the *old* target tag (still readable via `git log`/`git show` in the submodule, or by checking out the previous tag in a scratch clone) and the *new* tag, focused on just the lines the patch touches.
   - Judge: is this a trivial context-line drift (safe to regenerate the patch mechanically — e.g. `git apply --recount` or a manual small edit to the patch file, then re-verify with `git apply --check`) or a structural change (e.g. `VImage8.h`'s `VObject` class reshaped, `build/posix.sh`'s libvips-build block reorganized, `cplusplus/meson.build`'s `library('vips-cpp', ...)` sources list restructured)?
   - For structural changes: **STOP and report** what changed and what you think the patch needs to become, before actually rewriting it. This is exactly the kind of judgment call that shouldn't happen silently.

## Step 3: Re-check the wrapper symbol scope

Do not assume the symbol set in `patches/wrapper-symbols.json` is still complete or still necessary.

1. Re-run the exhaustive grep for bare `glib`/`gobject` calls across *every* file in the new `vendor/sharp/src/` (not just the files that had them last time):
   ```bash
   for f in $(git -C vendor/sharp ls-tree -r --name-only HEAD -- src/ | grep -E '\.(cc|h)$'); do
     git -C vendor/sharp show HEAD:"$f" | grep -noE '\bg_[a-z0-9_]+\s*\(' | while read -r m; do echo "$f: $m"; done
   done | sort -u
   ```
2. Also re-check whether `libvips`'s other public C++ headers (`VError8.h`, `VInterpolate8.h`, `VRegion8.h`, `VConnection8.h` — see `patches/wrapper-symbols.json`'s `headersChecked` for what was clean last time) have picked up the same inline-header pattern `VImage8.h` has.
3. Diff both results against `patches/wrapper-symbols.json`. Report: any symbols now called that aren't wrapped (add them — see `extra/glib_wrapper.c`/`.h` in `vendor/sharp-libvips`, following the existing pattern, remembering the `__attribute__((visibility("default")))` requirement), and any wrapped symbols no longer called anywhere (safe to leave as-is; removing them is low priority and not required).
4. Update `patches/wrapper-symbols.json` and the patch files to match — including the manifest's `targetVersions` field, which must always name the exact versions the manifest was verified against — then re-verify `git apply --check` on both.

## Step 4: Rebuild both phases

```bash
npm run build:libvips
npm run build:sharp
```

## Step 5: Run both gates

```bash
npm run test:gates
```

**If either gate fails**, follow the same loop this project's own development actually used — this is expected to happen at least once, not a sign something is broken:

1. Identify the specific symbol from the failure. Gate 1 (sharp's test suite) failures that mention `undefined symbol: <name>` name it directly, as does gate 2's failure mode if it manifests the same way; a genuine segfault in gate 2 means a wrapped symbol still isn't taking effect somewhere (re-check `objdump -T` on the rebuilt `libvips-cpp.so` for that symbol in both directions before assuming it's a *new* symbol).
2. Add it to the wrapper set (`extra/glib_wrapper.c`/`.h`, `patches/wrapper-symbols.json`, and the relevant call-site patch), regenerate both patch files, rebuild, re-run gates.
3. **Bound this to 3 automatic iterations.** If gates still aren't green after 3 rounds, **STOP and report** a clear summary of what's still failing, rather than continuing to loop. Something more fundamental is likely different about this version.

## Step 6: Re-verify

1. `objdump -T` on the rebuilt `libvips-cpp.so`, checking **every** symbol in `patches/wrapper-symbols.json` in both directions (bare name absent, `vips_<name>` present as defined + global).
2. `readelf -d` on the rebuilt `sharp.node` addon — confirm `DT_RPATH` (not `DT_RUNPATH`) once repackaged (see Step 7).
3. `npm run package`.

## Step 7: Prepare (but do not execute) the release

```bash
npm run release <new-version>-electron.0
```

This runs the full pipeline again, bumps `package/package.json`'s version, and prints the remaining manual steps. **Do not run `npm publish` yourself, and do not push/tag without explicit confirmation.** Instead:

1. Write a `CHANGELOG.md` entry summarizing: the new upstream version, any patch adjustments made and why (link back to what Step 2 found), any wrapper-symbol changes (link back to what Step 3 found), and confirmation that both gates pass.
2. **STOP and report** a summary to the user: what changed, what (if anything) needed judgment calls along the way, and that this is ready for their review before they decide to commit/tag/publish. Publishing is always an explicit, separate, human-confirmed action — never something this command does on its own, no matter how cleanly everything above went.
