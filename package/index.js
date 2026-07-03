// @janhapke/sharp-electron — Electron-safe replacement for sharp on Linux.
// See ../README.md for why this exists.
//
// The bug this project patches (two independently-loaded copies of glib
// colliding inside Electron's Linux binary) doesn't exist on macOS/Windows —
// so everywhere except linux-x64, this re-exports the real, unmodified
// `sharp` (declared as a normal dependency in package.json; npm installs the
// right platform binary for it automatically, same as any other consumer).
//
// On linux-x64: libvips-cpp.so sits next to the .node addon in
// linux-x64/sharp/src/build/Release/ — the addon's RPATH is set to $ORIGIN at
// package-build time (scripts/package-local.sh, via patchelf --force-rpath),
// so the dynamic linker finds it deterministically. Don't try to point at it
// via process.env.LD_LIBRARY_PATH instead: glibc parses that once at process
// start, not per dlopen() call, so setting it here doesn't reliably work.
//
// linux on any other arch (arm64, etc.): no patched build exists yet. Throw a
// clear, specific error here rather than silently falling back to real
// `sharp` — that fallback would just defer the exact crash this package
// exists to fix to whenever a real image gets decoded, instead of failing
// loudly at require() time.
if (process.platform === 'linux') {
  if (process.arch === 'x64') {
    module.exports = require('./linux-x64/sharp/dist/index.cjs');
  } else {
    throw new Error(
      `@janhapke/sharp-electron has no patched build for linux-${process.arch} yet ` +
      '(only linux-x64 so far). Falling back to the real `sharp` package here would ' +
      'silently reintroduce the Electron/glib crash this package exists to fix — see ' +
      'this package\'s README for details, and consider contributing a build for this arch.'
    );
  }
} else {
  module.exports = require('sharp');
}
