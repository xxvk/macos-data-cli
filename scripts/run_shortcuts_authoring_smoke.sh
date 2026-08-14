#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
SOURCE="$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri"
TMP_DIR="$(mktemp -d /tmp/macos-data-shortcuts-author.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 700 "$TMP_DIR"

[[ -x "$CLI" ]] || { echo "CLI not found: $CLI" >&2; exit 1; }
[[ -f "$SOURCE" ]] || { echo "Fixture not found" >&2; exit 1; }

"$CLI" shortcuts author validate --source "$SOURCE" --format json >"$TMP_DIR/validate.json"
"$CLI" shortcuts author build --source "$SOURCE" --output "$TMP_DIR/fixture.shortcut" --format json >"$TMP_DIR/build.json"

rg -q '"ok"[[:space:]]*:[[:space:]]*true' "$TMP_DIR/validate.json"
rg -q '"actionCount"[[:space:]]*:[[:space:]]*1' "$TMP_DIR/validate.json"
rg -q '"compilerVersion"[[:space:]]*:[[:space:]]*"2\.3\.' "$TMP_DIR/validate.json"
rg -q '"ok"[[:space:]]*:[[:space:]]*true' "$TMP_DIR/build.json"
rg -q '"signingMode"[[:space:]]*:[[:space:]]*"people-who-know-me"' "$TMP_DIR/build.json"
[[ -s "$TMP_DIR/fixture.shortcut" ]]
[[ "$(stat -f '%Lp' "$TMP_DIR/fixture.shortcut")" == "600" ]]

if rg -qi '#define|macos data 071 fixture|macos-data 0\.7\.1 fixture' "$TMP_DIR/validate.json" "$TMP_DIR/build.json"; then
  echo "Authoring result leaked source content or the fixture name" >&2
  exit 1
fi

echo "Shortcuts authoring validate/build smoke passed (imported=false)."
