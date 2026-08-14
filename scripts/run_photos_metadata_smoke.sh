#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data.app/Contents/MacOS/macos-data}"
APP="${MACOS_DATA_APP:-}"
START="${PHOTOS_SMOKE_START:-$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')}"
END="${PHOTOS_SMOKE_END:-$(date -u -v+1d '+%Y-%m-%dT%H:%M:%SZ')}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$APP" ]]; then
  [[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
else
  [[ -x "$CLI" ]] || { echo "CLI not found or not executable: $CLI" >&2; exit 1; }
fi
command -v jq >/dev/null || { echo "Photos metadata smoke requires jq." >&2; exit 1; }

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

run_cli "$TMP_DIR/query.json" photos query --start "$START" --end "$END" --limit 5 --format json
jq -e '.ok == true and .data.complete == true and (.data.items | type == "array") and ([.data.items[].location] | all(. == null))' "$TMP_DIR/query.json" >/dev/null

count="$(jq -r '.data.items | length' "$TMP_DIR/query.json")"
truncated="$(jq -r '.data.truncated' "$TMP_DIR/query.json")"
get_checked=false
if [[ "$count" -gt 0 ]]; then
  asset_id="$(jq -r '.data.items[0].id' "$TMP_DIR/query.json")"
  run_cli "$TMP_DIR/get.json" photos get --id "$asset_id" --format json
  jq -e '.ok == true and (.data.id | startswith("photo_")) and .data.location == null and .data.contentAvailability == "unknown"' "$TMP_DIR/get.json" >/dev/null
  get_checked=true
fi

echo "Photos metadata smoke passed: complete=true returned=$count truncated=$truncated getChecked=$get_checked locationOmitted=true"
