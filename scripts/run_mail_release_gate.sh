#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_AUTOMATION=false

if [[ "${1:-}" == "--with-automation" ]]; then
  WITH_AUTOMATION=true
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "usage: $0 [--with-automation]" >&2
  exit 64
fi

cd "$ROOT_DIR"
BUILD_CACHE_DIR="$ROOT_DIR/.build/local-cache"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export SWIFTPM_CONFIG_DIR="$BUILD_CACHE_DIR/swiftpm-config"
export XDG_CACHE_HOME="$BUILD_CACHE_DIR/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"

mkdir -p "$SWIFTPM_CONFIG_DIR" "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"

swift test
swift build -c release
bash scripts/build_debug_app.sh
plutil -lint scripts/macos-data-app-Info.plist scripts/macos-data.entitlements
codesign --verify --deep --strict .build/debug/macos-data.app
automation_entitlement="$(
  codesign -d --entitlements :- .build/debug/macos-data.app 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.automation\.apple-events' raw -o - -
)"
if [[ "$automation_entitlement" != "true" ]]; then
  echo "Mail Automation entitlement is missing from the signed Debug app." >&2
  exit 1
fi
bash scripts/run_mail_doctor_smoke.sh --require-fast-path
bash scripts/run_mail_metadata_smoke.sh
bash scripts/run_mail_content_smoke.sh
bash scripts/run_mail_attachment_smoke.sh

if [[ "$WITH_AUTOMATION" == true ]]; then
  bash scripts/run_mail_automation_smoke.sh --gui-session
fi

git diff --check
echo "Mail 0.2 local release gate passed (automation=$WITH_AUTOMATION)."
