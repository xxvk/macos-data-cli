#!/usr/bin/env bash
set -euo pipefail

# Privacy-minimized live smoke for the read-only Messages adapter.
# Prints aggregate counts and truncation/completeness only. It never prints
# message bodies, participant handles, or identifiers, and it stops before any
# query when Full Disk Access is unavailable.

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
command -v jq >/dev/null || { echo "Messages read smoke requires jq." >&2; exit 1; }

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
      echo "Messages app command produced no JSON output." >&2
      exit 1
    fi
  else
    "$CLI" "$@" >"$output_path"
  fi
}

run_cli "$TMP_DIR/permission.json" messages permission --format json
readable="$(jq -r '.data.readable' "$TMP_DIR/permission.json")"
fda="$(jq -r '.data.fullDiskAccess' "$TMP_DIR/permission.json")"

if [[ "$readable" != "true" ]]; then
  echo "Messages read smoke stopped before query: readable=$readable fullDiskAccess=$fda" >&2
  exit 7
fi

run_cli "$TMP_DIR/recent.json" messages recent --limit 5 --format json
count="$(jq '.data.items | length' "$TMP_DIR/recent.json")"
truncated="$(jq -r '.data.truncated' "$TMP_DIR/recent.json")"
complete="$(jq -r '.data.complete' "$TMP_DIR/recent.json")"
cursor="$(jq -r '.data.nextCursor // "none"' "$TMP_DIR/recent.json")"

echo "Messages read smoke passed: sampleCount=$count truncated=$truncated complete=$complete nextCursor=$cursor privateOutputRemovedOnExit=true"
