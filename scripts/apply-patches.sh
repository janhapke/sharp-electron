#!/usr/bin/env bash
# Applies this project's patches to the vendored submodules. Idempotent: safe
# to run whether the submodules are pristine (fresh clone) or already patched
# (a previous run of this script, or manual dev work) — skips anything
# already applied rather than erroring.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

apply_patch() {
  local submodule="$1"
  local patch="$ROOT/$2"

  if ! git -C "$submodule" apply --check "$patch" 2>/dev/null; then
    if git -C "$submodule" apply --check --reverse "$patch" 2>/dev/null; then
      echo "already applied: $2 -> $submodule (skipping)"
      return 0
    fi
    echo "error: $2 does not apply cleanly to $submodule, and isn't already applied either." >&2
    echo "       Upstream source likely changed in the area this patch touches — see the" >&2
    echo "       /rebuild-for-version command (.claude/commands/rebuild-for-version.md) for" >&2
    echo "       how to diagnose and update the patch." >&2
    exit 1
  fi

  git -C "$submodule" apply "$patch"
  echo "applied: $2 -> $submodule"
}

apply_patch vendor/sharp-libvips patches/sharp-libvips-glib-wrapper.patch
apply_patch vendor/sharp patches/sharp-glib-calls.patch
