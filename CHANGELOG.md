# Changelog

## 0.35.4-electron.0

Targets `sharp` `0.35.4` / `sharp-libvips` `1.3.3` (libvips `8.18.6`, up from `8.18.3`).

- The Electron/glib collision bug still reproduces on a stock, unpatched build at these versions (confirmed via `test/electron-crash-repro.js` before applying any patches) — upstream has not fixed it independently.
- Both existing patches (`patches/sharp-libvips-glib-wrapper.patch`, `patches/sharp-glib-calls.patch`) applied cleanly against the new tags with no structural changes needed.
- Wrapper symbol set grew from 7 to 8: `g_value_unset`, called from `VImage8.h`'s `VOption::Pair` destructor (header-only, inlined into `sharp.node` wherever `vips::VOption` is used — the same class of risk as the original `g_object_ref`/`g_object_unref` crash cause). This call is present since at least libvips `8.18.3`, not something newly introduced by this bump; it was missed by the original grep-based pass, which covered `sharp`'s own source exhaustively but only checked `VImage8.h` for the two already-known symbols rather than re-scanning it fully. Found during this version bump's routine header re-check, before either test gate ran. See `patches/wrapper-symbols.json` for full details.
- No other symbol changes: a fresh exhaustive grep of every `.cc`/`.h` file in `sharp`'s `src/` found the same symbol set as before, and libvips's other public C++ headers (`VError8.h`, `VInterpolate8.h`, `VRegion8.h`, `VConnection8.h`) remain clean of the inline-glib-call pattern.
- Both test gates pass: `sharp`'s own upstream test suite (same pre-existing, unrelated `test/unit/esm.mjs` failure as prior releases) and the Electron crash regression test.
- `objdump -T` confirms all 8 wrapper symbols are correctly exported/hidden in both directions; `readelf -d` confirms the packaged addon still uses `DT_RPATH` (not `DT_RUNPATH`).

## 0.35.3-electron.1

- Fixed the "`sharp` is also a direct dependency" install recipe in the README: the documented `"overrides": { "sharp": "$sharp" }` silently broke this package's own non-Linux fallback and TypeScript types, because npm overrides recurse by default and rewrote this package's own internal `sharp` dependency back into a circular self-reference (`require('sharp')` inside the fallback resolved to an empty `{}`, no install-time error). Fixed by documenting the nested override form instead (`"sharp": { ".": "$sharp", "sharp": "0.35.3" }`), verified against a real install on both the patched and simulated-fallback paths.
- No code or binary changes — same build as 0.35.3-electron.0, republished so the corrected install docs are what npmjs.com actually shows.

## 0.35.3-electron.0

First release, targeting `sharp` `0.35.3` / `sharp-libvips` `1.3.2`.

- Rebuilds `libvips-cpp.so` with the full `glib`/`gobject` symbol surface hidden (upstream hides only `g_param_spec_types`), re-exporting the seven symbols `sharp`'s native addon actually needs under renamed `vips_g_*` wrappers — see `patches/wrapper-symbols.json` for the full list and per-symbol reasoning.
- Rebuilds `sharp`'s native addon (and, transitively, `libvips`'s inline `VImage8.h` header) to call those wrappers instead of the now-hidden bare `glib` functions. This eliminates the symbol collision with Electron's own `glib` that segfaults image decoding on Linux ([electron/electron#46323](https://github.com/electron/electron/issues/46323)).
- The compiled addon resolves its co-located `libvips-cpp.so` via old-style `DT_RPATH` (`$ORIGIN`), so it deterministically wins over any other copy reachable through the consumer's `LD_LIBRARY_PATH` or `node_modules`.
- Cross-platform dispatch: `linux-x64` uses the patched build; any other Linux architecture throws a clear error at load time rather than silently using an unpatched build; macOS/Windows re-export the real, unmodified `sharp`.
- Verified against `sharp`'s own upstream test suite (1804/1811 passing; the one failure is a pre-existing, unrelated Node ESM/CJS interop quirk that fails identically against stock `sharp`) and a dedicated Electron crash-regression test, plus end-to-end in a real consuming Electron application.
- The full build pipeline is scripted and Docker-only (`npm run build`), with CI covering both the Linux pipeline and the macOS/Windows fallback path.
- Ships TypeScript types (`package/index.d.ts`, forwarding to `sharp`'s own declarations) so the `overrides` install keeps full type information on both the patched and fallback paths.

Known gaps: CI has not yet produced a green run on real macOS/Windows runners, and `linux-arm64` has no patched build (it fails loudly rather than silently).
