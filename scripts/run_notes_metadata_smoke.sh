#!/usr/bin/env bash
set -euo pipefail

APP="${MACOS_DATA_APP:-}"
[[ -n "$APP" && -d "$APP" ]] || { echo "Set MACOS_DATA_APP to a signed app bundle." >&2; exit 1; }
command -v jq >/dev/null || { echo "Notes metadata smoke requires jq." >&2; exit 1; }

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
    echo "Notes metadata smoke failed without exposing private response data." >&2
    exit 1
  }
}

run_app "$TMP_DIR/permission.json" notes permission --format json
jq -e '.ok == true and .data.access == "available" and .data.readable == true and .data.requested == false' \
  "$TMP_DIR/permission.json" >/dev/null

run_app "$TMP_DIR/query.json" notes query --limit 200 --format json
jq -e '.ok == true and (.data.items | type == "array") and .data.limit == 200 and (.data.complete | type == "boolean")' \
  "$TMP_DIR/query.json" >/dev/null

note_count="$(jq -r '.data.items | length' "$TMP_DIR/query.json")"
complete="$(jq -r '.data.complete' "$TMP_DIR/query.json")"
truncated="$(jq -r '.data.truncated' "$TMP_DIR/query.json")"
locked_count="$(jq -r '[.data.items[] | select(.passwordProtected == true)] | length' "$TMP_DIR/query.json")"
shared_count="$(jq -r '[.data.items[] | select(.shared == true)] | length' "$TMP_DIR/query.json")"
creation_date_count="$(jq -r '[.data.items[] | select(.creationDate != null)] | length' "$TMP_DIR/query.json")"
modification_date_count="$(jq -r '[.data.items[] | select(.modificationDate != null)] | length' "$TMP_DIR/query.json")"
metadata_get="not_run"
if [[ "$note_count" -gt 0 ]]; then
  note_id="$(jq -r '.data.items[0].id' "$TMP_DIR/query.json")"
  run_app "$TMP_DIR/get.json" notes get --id "$note_id" --format json
  jq -e --arg id "$note_id" \
    '.ok == true and .data.note.id == $id and .data.bodyFormat == "none" and .data.body == null and .data.bodyBytes == null' \
    "$TMP_DIR/get.json" >/dev/null
  metadata_get="passed"
fi

echo "Notes metadata smoke passed: notes=$note_count complete=$complete truncated=$truncated locked=$locked_count shared=$shared_count withCreationDate=$creation_date_count withModificationDate=$modification_date_count metadataGet=$metadata_get privateOutputRemovedOnExit=true"
