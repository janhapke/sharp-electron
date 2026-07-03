#!/usr/bin/env bash
# The single documented entry point: patches -> Phase A -> Phase B -> both
# gates -> local package. Stops on first failure. Requires only Docker on
# the host (see README.md's "Building from source" section).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "### 1/4 Phase A: libvips ###"
./scripts/build-libvips.sh

echo ""
echo "### 2/4 Phase B: sharp ###"
./scripts/build-sharp.sh

echo ""
echo "### 3/4 Test gates ###"
./scripts/run-gates.sh

echo ""
echo "### 4/4 Package (local testing) ###"
./scripts/package-local.sh

echo ""
echo "All done. See README.md's 'Local testing against an unpublished build' section for how to consume package/ from another project."
