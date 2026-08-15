#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_MAIL_AUTOMATION=false
INSTALLED_CLI=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-mail-automation) WITH_MAIL_AUTOMATION=true; shift ;;
    --installed-cli) [[ $# -ge 2 ]] || exit 64; INSTALLED_CLI="$2"; shift 2 ;;
    *) echo "usage: $0 [--with-mail-automation] [--installed-cli <path>]" >&2; exit 64 ;;
  esac
done

cd "$ROOT_DIR"
BUILD_CACHE_DIR="$ROOT_DIR/.build/local-cache"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR
export SWIFTPM_CONFIG_DIR="$BUILD_CACHE_DIR/swiftpm-config"
export XDG_CACHE_HOME="$BUILD_CACHE_DIR/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"
mkdir -p "$SWIFTPM_CONFIG_DIR" "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"

EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$EXPECTED_VERSION" == "0.8.1" ]] || {
  echo "0.8.1 release gate requires VERSION=0.8.1; observed=$EXPECTED_VERSION" >&2
  exit 1
}

plutil -lint Sources/macos-data/Info.plist scripts/macos-data-app-Info.plist scripts/macos-data.entitlements >/dev/null
rg -q '^## 0\.7\.2 — ' CHANGELOG.md
rg -q 'current source release is 0\.8\.1' README.md
rg -q '当前源码版本为 0\.8\.1' README_CN.md

bash scripts/run_swift_tests.sh --quiet
swift build -c release

RELEASE_CLI="$ROOT_DIR/.build/release/macos-data"
RELEASE_VERSION="$("$RELEASE_CLI" --version)"
SOURCE_BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - Sources/macos-data/Info.plist)"
SOURCE_BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - Sources/macos-data/Info.plist)"
DEBUG_BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - scripts/macos-data-app-Info.plist)"
DEBUG_BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - scripts/macos-data-app-Info.plist)"
for observed in "$RELEASE_VERSION" "$SOURCE_BUNDLE_VERSION" "$SOURCE_BUILD_VERSION" "$DEBUG_BUNDLE_VERSION" "$DEBUG_BUILD_VERSION"; do
  [[ "$observed" == "$EXPECTED_VERSION" ]] || {
    echo "Release version drift: expected=$EXPECTED_VERSION observed=$observed" >&2
    exit 1
  }
done

bash scripts/build_debug_app.sh >/dev/null
DEBUG_APP_SOURCE="$ROOT_DIR/.build/debug/macos-data.app"
DEBUG_APP_TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$DEBUG_APP_TEMP_ROOT"' EXIT
DEBUG_APP="$DEBUG_APP_TEMP_ROOT/macos-data.app"
ditto --norsrc --noextattr "$DEBUG_APP_SOURCE" "$DEBUG_APP"
xattr -cr "$DEBUG_APP"
codesign --force --sign - --entitlements "$ROOT_DIR/scripts/macos-data.entitlements" "$DEBUG_APP" >/dev/null
DEBUG_CLI="$DEBUG_APP/Contents/MacOS/macos-data"
codesign --verify --deep --strict "$DEBUG_APP"
AUTOMATION_ENTITLEMENT="$(
  codesign -d --entitlements :- "$DEBUG_APP" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.automation\.apple-events' raw -o - -
)"
[[ "$AUTOMATION_ENTITLEMENT" == "true" ]] || {
  echo "Mail Automation entitlement is missing from the signed Debug app." >&2
  exit 1
}
PHOTOS_ENTITLEMENT="$(
  codesign -d --entitlements :- "$DEBUG_APP" 2>/dev/null \
    | plutil -extract 'com\.apple\.security\.personal-information\.photos-library' raw -o - -
)"
[[ "$PHOTOS_ENTITLEMENT" == "true" ]] || {
  echo "Photos Library entitlement is missing from the signed Debug app." >&2
  exit 1
}

MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_cli_contract_tests.sh --no-apply
MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_shortcuts_authoring_smoke.sh
MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_calendar_contract_tests.sh
CALENDAR_PREFLIGHT="$DEBUG_APP_TEMP_ROOT/calendar-sources.json"
set +e
"$DEBUG_CLI" calendar sources --format json >"$CALENDAR_PREFLIGHT" 2>&1
CALENDAR_PREFLIGHT_EXIT=$?
set -e
if [[ "$CALENDAR_PREFLIGHT_EXIT" -eq 0 ]]; then
  MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_calendar_read_smoke.sh
  MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_calendar_dry_run_smoke.sh
elif [[ "$CALENDAR_PREFLIGHT_EXIT" -eq 5 ]] \
  && jq -e '.ok == false and .error.code == "CALENDAR_SOURCE_AMBIGUOUS"' "$CALENDAR_PREFLIGHT" >/dev/null; then
  echo "Calendar live smoke skipped: the host has multiple matching iCloud sources and the CLI failed closed as required."
else
  echo "Calendar live smoke preflight failed with an unexpected result." >&2
  jq -c '{ok,errorCode:.error.code}' "$CALENDAR_PREFLIGHT" >&2 2>/dev/null || true
  exit 1
fi

MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_doctor_smoke.sh --require-fast-path
MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_metadata_smoke.sh
MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_content_smoke.sh
MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_attachment_smoke.sh

if [[ "$WITH_MAIL_AUTOMATION" == true ]]; then
  MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_app_metadata_smoke.sh
  MACOS_DATA_CLI="$DEBUG_CLI" bash scripts/run_mail_automation_smoke.sh --gui-session
fi

if [[ -n "$INSTALLED_CLI" ]]; then
  bash scripts/run_installed_release_smoke.sh "$INSTALLED_CLI"
fi

git diff --check
echo "macos-data $EXPECTED_VERSION local release gate passed (mailAutomation=$WITH_MAIL_AUTOMATION installedSmoke=$([[ -n "$INSTALLED_CLI" ]] && echo true || echo false))."
echo "Real Calendar write gates are separately authorized and are not repeated by this release gate."
