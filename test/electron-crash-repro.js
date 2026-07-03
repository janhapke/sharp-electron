// Run via: ELECTRON_RUN_AS_NODE=1 ./node_modules/.bin/electron test/electron-crash-repro.js
//
// Reproduces (on an unpatched sharp/libvips Linux build) the SIGSEGV caused by
// two independently-loaded copies of glib colliding inside Electron's binary.
// See README.md for the full diagnosis.
//
// Expected on UNPATCHED sharp: step 1 succeeds, step 2 segfaults (process dies,
// no JS exception, no stack trace — that's the bug).
// Expected on a working @janhapke/sharp-electron build: both steps succeed.
//
// By default requires the top-level 'sharp' devDependency (the real,
// unpatched npm package — useful for confirming the bug still reproduces
// before any patching). Set SHARP_MODULE_PATH to an
// absolute path to test a different build instead — e.g. gate 2 in
// scripts/run-gates.sh points this at the freshly-built vendor/sharp.

const sharp = require(process.env.SHARP_MODULE_PATH || 'sharp');

async function main() {
  console.log(`sharp ${sharp.versions.sharp} / vips ${sharp.versions.vips}`);
  console.log(`node ${process.version}, electron ${process.versions.electron}`);

  console.log('[1/2] encode: raw pixel buffer -> JPEG (expected to always succeed)');
  const width = 64;
  const height = 64;
  const raw = Buffer.alloc(width * height * 3, 128);
  const jpeg = await sharp(raw, { raw: { width, height, channels: 3 } })
    .jpeg()
    .toBuffer();
  console.log(`    ok — produced ${jpeg.length}-byte JPEG`);

  console.log('[2/2] decode: real compressed JPEG buffer via .metadata() + .resize().toBuffer()');
  console.log('    (this is the step that segfaults on an unpatched build under Electron)');
  const meta = await sharp(jpeg).metadata();
  console.log(`    metadata() ok — ${meta.width}x${meta.height}`);
  const resized = await sharp(jpeg).resize(32, 32).toBuffer();
  console.log(`    resize().toBuffer() ok — ${resized.length}-byte result`);

  console.log('PASS: no crash — decode path survived under Electron');
  process.exit(0);
}

main().catch((err) => {
  console.error('FAIL (JS exception, not the native segfault this test targets):', err);
  process.exit(1);
});
