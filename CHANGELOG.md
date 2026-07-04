# Changelog

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
