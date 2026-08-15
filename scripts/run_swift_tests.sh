#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${MPIA_SWIFT_SCRATCH_PATH:-${TMPDIR:-/tmp}/mpia-cli-swiftpm-tests}"
CACHE_ROOT="${MPIA_SWIFT_CACHE_PATH:-${TMPDIR:-/tmp}/mpia-cli-swiftpm-cache}"

mkdir -p "$SCRATCH_PATH" "$CACHE_ROOT/swiftpm" "$CACHE_ROOT/clang"
chmod 700 "$SCRATCH_PATH" "$CACHE_ROOT" "$CACHE_ROOT/swiftpm" "$CACHE_ROOT/clang"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$CACHE_ROOT}"
export SWIFTPM_CONFIG_DIR="${SWIFTPM_CONFIG_DIR:-$CACHE_ROOT/swiftpm}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$CACHE_ROOT/clang}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$CACHE_ROOT/clang}"
cd "$ROOT_DIR"

# Xcode 27 may attach File Provider/Finder metadata to newly generated XCTest
# bundles when the package lives in iCloud Drive. codesign rejects those
# attributes. A local scratch path keeps generated test bundles outside the
# synced workspace without modifying source files or the ordinary .build tree.
swift test --scratch-path "$SCRATCH_PATH" "$@"
