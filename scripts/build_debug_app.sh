#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/debug/macos-data.app"
BUILD_CACHE_DIR="$ROOT_DIR/.build/local-cache"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export SWIFTPM_CONFIG_DIR="$BUILD_CACHE_DIR/swiftpm-config"
export XDG_CACHE_HOME="$BUILD_CACHE_DIR/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"

mkdir -p "$SWIFTPM_CONFIG_DIR" "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"

swift build

mkdir -p "$APP_DIR/Contents/MacOS"
cp "$ROOT_DIR/.build/debug/macos-data" "$APP_DIR/Contents/MacOS/macos-data"
cp "$ROOT_DIR/scripts/macos-data-app-Info.plist" "$APP_DIR/Contents/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --sign - --entitlements "$ROOT_DIR/scripts/macos-data.entitlements" "$APP_DIR"

echo "$APP_DIR"
