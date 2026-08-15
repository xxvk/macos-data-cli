#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
APP="${MPIA_APP:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$APP" ]]; then
  [[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
else
  [[ -x "$CLI" ]] || { echo "CLI not found or not executable: $CLI" >&2; exit 1; }
fi
command -v jq >/dev/null || { echo "Photos read smoke requires jq." >&2; exit 1; }

run_cli() {
  local output_path="$1"
  shift

  if [[ -n "$APP" ]]; then
    local error_path="$output_path.stderr"
    /usr/bin/open -n -W -o "$output_path" --stderr "$error_path" "$APP" --args "$@" >/dev/null 2>&1 || true
    for _ in {1..50}; do
      [[ -s "$output_path" ]] && break
      sleep 0.1
    done
    if [[ ! -s "$output_path" ]]; then
      [[ -s "$error_path" ]] && sed -n '1,40p' "$error_path" >&2
      echo "Photos app command produced no JSON output." >&2
      exit 1
    fi
  else
    "$CLI" "$@" >"$output_path"
  fi
}

run_cli "$TMP_DIR/permission.json" photos permission --format json
access="$(jq -er '.data.access' "$TMP_DIR/permission.json")"
readable="$(jq -r '.data.readable' "$TMP_DIR/permission.json")"
complete="$(jq -r '.data.complete' "$TMP_DIR/permission.json")"

if [[ "$readable" != "true" ]]; then
  echo "Photos read smoke stopped before collection fetch: access=$access readable=false" >&2
  exit 7
fi

run_cli "$TMP_DIR/albums.json" photos albums --kind all --limit 200 --format json
jq -e '.ok == true and (.data.items | type == "array")' "$TMP_DIR/albums.json" >/dev/null

total="$(jq -r '.data.items | length' "$TMP_DIR/albums.json")"
user_albums="$(jq -r '[.data.items[] | select(.kind == "userAlbum")] | length' "$TMP_DIR/albums.json")"
smart_albums="$(jq -r '[.data.items[] | select(.kind == "smartAlbum")] | length' "$TMP_DIR/albums.json")"
folders="$(jq -r '[.data.items[] | select(.kind == "folder")] | length' "$TMP_DIR/albums.json")"
truncated="$(jq -r '.data.truncated' "$TMP_DIR/albums.json")"
page_complete="$(jq -r '.data.complete' "$TMP_DIR/albums.json")"

[[ "$page_complete" == "$complete" ]] || {
  echo "Photos permission completeness and album page completeness disagree." >&2
  exit 1
}

echo "Photos read smoke passed: access=$access complete=$complete total=$total userAlbums=$user_albums smartAlbums=$smart_albums folders=$folders truncated=$truncated"
