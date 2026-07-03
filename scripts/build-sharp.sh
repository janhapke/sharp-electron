#!/usr/bin/env bash
# Phase B: patch + rebuild sharp's native addon against the Phase A libvips,
# inside a Docker image matching sharp's own official CI build environment
# (rockylinux + gcc-toolset-14 + Node + patchelf). Never touches the host.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

./scripts/apply-patches.sh

if [ ! -d "dist/linux-x64/lib/pkgconfig" ]; then
  echo "error: dist/linux-x64 not found — run scripts/build-libvips.sh first" >&2
  exit 1
fi

docker build -f scripts/sharp-build.Dockerfile -t sharp-electron-build scripts/

docker run --rm \
  -v "$ROOT:$ROOT" \
  -w "$ROOT/vendor/sharp" \
  -e PKG_CONFIG_PATH="$ROOT/dist/linux-x64/lib/pkgconfig" \
  -e SHARP_FORCE_GLOBAL_LIBVIPS=1 \
  -e LD_LIBRARY_PATH="$ROOT/dist/linux-x64/lib" \
  sharp-electron-build sh -c "npm install && npm run build:dist && npm run build"

echo "Phase B done: vendor/sharp/src/build/Release/sharp-linux-x64-*.node"
