// The patched linux-x64 build and the real sharp fallback share sharp's exact
// public API (only internals are patched), and this package always installs
// real `sharp` as a dependency, aliased to 'sharp-upstream' (see
// package.json) — so its own types are the correct types for both branches
// of index.js's runtime dispatch.
//
// Deliberately imports 'sharp-upstream', not 'sharp': a consumer using this
// package via an `overrides`/`resolutions` rule targeting the name "sharp"
// (the documented, recommended install method — see README.md's Usage
// section) would otherwise have that same rule recurse into this internal
// import, since npm/yarn overrides apply to every dependency edge named
// "sharp" anywhere in the tree, including this package's own. The result
// isn't a resolution error — it silently dedupes this import back onto this
// package itself, an unresolvable circular type reference that surfaces as
// spurious "has no exported member" / "can only be referenced with
// ECMAScript imports" errors from consumers' own type-checkers, without any
// error at install time. Aliasing the dependency's name sidesteps the
// collision structurally, the same way this package's own name differs from
// "sharp" for the exact same reason.
import sharp = require('sharp-upstream');
export = sharp;
