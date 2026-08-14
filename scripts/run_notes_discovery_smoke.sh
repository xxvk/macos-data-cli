#!/usr/bin/env bash
set -euo pipefail

APP="${MACOS_DATA_APP:-}"
[[ -n "$APP" && -d "$APP" ]] || { echo "Set MACOS_DATA_APP to a signed app bundle." >&2; exit 1; }
command -v jq >/dev/null || { echo "Notes discovery smoke requires jq." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_app() {
  local output_path="$1"
  shift
  local error_path="$output_path.stderr"
  /usr/bin/open -n -W -o "$output_path" --stderr "$error_path" "$APP" --args "$@" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    [[ -s "$output_path" || -s "$error_path" ]] && break
    sleep 0.1
  done
  [[ -s "$output_path" ]] || {
    echo "Notes discovery smoke failed without exposing private response data." >&2
    exit 1
  }
}

run_app "$TMP_DIR/permission.json" notes permission --format json
jq -e '.ok == true and .data.access == "available" and .data.readable == true and .data.requested == false' \
  "$TMP_DIR/permission.json" >/dev/null

run_app "$TMP_DIR/accounts.json" notes accounts --format json
run_app "$TMP_DIR/folders.json" notes folders --limit 200 --format json

jq -e '.ok == true and (.data.accounts | type == "array") and (.data.complete | type == "boolean")' \
  "$TMP_DIR/accounts.json" >/dev/null
jq -e '.ok == true and (.data.items | type == "array") and .data.limit == 200 and (.data.complete | type == "boolean")' \
  "$TMP_DIR/folders.json" >/dev/null

account_count="$(jq -r '.data.accounts | length' "$TMP_DIR/accounts.json")"
folder_count="$(jq -r '.data.items | length' "$TMP_DIR/folders.json")"
maximum_depth="$(jq -r '[.data.items[].depth] | max // 0' "$TMP_DIR/folders.json")"
shared_count="$(jq -r '[.data.items[] | select(.shared == true)] | length' "$TMP_DIR/folders.json")"
accounts_complete="$(jq -r '.data.complete' "$TMP_DIR/accounts.json")"
folders_complete="$(jq -r '.data.complete' "$TMP_DIR/folders.json")"
truncated="$(jq -r '.data.truncated' "$TMP_DIR/folders.json")"

echo "Notes discovery smoke passed: accounts=$account_count folders=$folder_count maximumDepth=$maximum_depth sharedFolders=$shared_count accountsComplete=$accounts_complete foldersComplete=$folders_complete truncated=$truncated privateOutputRemovedOnExit=true"
