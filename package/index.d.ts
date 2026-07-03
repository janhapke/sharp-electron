// The patched linux-x64 build and the real sharp fallback share sharp's exact
// public API (only internals are patched), and this package always installs
// real `sharp` as a dependency (see package.json) — so its own types are the
// correct types for both branches of index.js's runtime dispatch.
import sharp = require('sharp');
export = sharp;
