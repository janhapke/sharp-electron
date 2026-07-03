#!/usr/bin/env bash
# Phase A: patch + rebuild libvips, then set up dist/linux-x64/ (the .so +
# hand-written .pc files sharp's build points at via SHARP_FORCE_GLOBAL_LIBVIPS).
# Docker-only — no toolchain needed on the host.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

./scripts/apply-patches.sh

VERSION_VIPS=$(grep '^VERSION_VIPS=' vendor/sharp-libvips/versions.properties | cut -d= -f2)
VERSION_GLIB=$(grep '^VERSION_GLIB=' vendor/sharp-libvips/versions.properties | cut -d= -f2)
DIST_DIR="$ROOT/dist/linux-x64"

cd vendor/sharp-libvips
rm -f "sharp-libvips-linux-x64.tar.gz"
./build.sh linux-x64
cd "$ROOT"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/lib/pkgconfig"
tar xzf "vendor/sharp-libvips/sharp-libvips-linux-x64.tar.gz" -C "$DIST_DIR"
ln -sf "libvips-cpp.so.${VERSION_VIPS}" "$DIST_DIR/lib/libvips-cpp.so"

# binding.gyp's `use_global_libvips` branch queries pkg-config for all three
# of these separately (`pkg-config --cflags-only-I vips-cpp vips glib-2.0`) —
# the packaged tarball intentionally strips pkgconfig/ (it's meant for npm
# consumption, not for pointing other builds at), so these are authored here.
cat > "$DIST_DIR/lib/pkgconfig/vips-cpp.pc" <<EOF
prefix=$DIST_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: vips-cpp
Description: C++ API for vips8 image processing library (sharp-electron build)
Version: ${VERSION_VIPS}
Libs: -L\${libdir} -lvips-cpp
Cflags: -I\${includedir} -I\${includedir}/glib-2.0 -I\${libdir}/glib-2.0/include
EOF

cat > "$DIST_DIR/lib/pkgconfig/vips.pc" <<EOF
prefix=$DIST_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: vips
Description: Image processing library (sharp-electron build)
Version: ${VERSION_VIPS}
Cflags: -I\${includedir}
EOF

cat > "$DIST_DIR/lib/pkgconfig/glib-2.0.pc" <<EOF
prefix=$DIST_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: glib-2.0
Description: C Utility Library (sharp-electron build)
Version: ${VERSION_GLIB}
Cflags: -I\${includedir}/glib-2.0 -I\${libdir}/glib-2.0/include
EOF

echo "Phase A done: $DIST_DIR (libvips ${VERSION_VIPS}, glib ${VERSION_GLIB})"
