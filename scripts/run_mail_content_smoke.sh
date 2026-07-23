#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$CLI" ]]; then
  echo "CLI not found or not executable. Run: swift build" >&2
  exit 1
fi

"$CLI" mail query --limit 50 --format json >"$TMP_DIR/query.json"

selected_id=""
for index in $(seq 0 49); do
  id="$(plutil -extract "data.messages.$index.id" raw -o - "$TMP_DIR/query.json" 2>/dev/null || true)"
  [[ -n "$id" ]] || break
  "$CLI" mail get --id "$id" --content metadata --format json >"$TMP_DIR/metadata.json"
  cache_state="$(plutil -extract data.cacheState raw -o - "$TMP_DIR/metadata.json" 2>/dev/null || true)"
  if [[ "$cache_state" == "complete" ]]; then
    selected_id="$id"
    break
  fi
done

if [[ -z "$selected_id" ]]; then
  echo "No complete cached EMLX message found in the bounded sample." >&2
  exit 1
fi

"$CLI" mail get --id "$selected_id" --content text --format json >"$TMP_DIR/text.json"
rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite_emlx"' "$TMP_DIR/text.json"
rg -q '"cacheState"[[:space:]]*:[[:space:]]*"complete"' "$TMP_DIR/text.json"
rg -q '"incomplete"[[:space:]]*:[[:space:]]*false' "$TMP_DIR/text.json"

"$CLI" mail get --id "$selected_id" --content raw --output "$TMP_DIR/message.eml" --format json >"$TMP_DIR/raw-result.json"
test -s "$TMP_DIR/message.eml"
rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite_emlx"' "$TMP_DIR/raw-result.json"
rg -q '"output"[[:space:]]*:[[:space:]]*"file"' "$TMP_DIR/raw-result.json"

before_hash="$(shasum -a 256 "$TMP_DIR/message.eml" | awk '{print $1}')"
set +e
"$CLI" mail get --id "$selected_id" --content raw --output "$TMP_DIR/message.eml" --format json >"$TMP_DIR/overwrite.json" 2>&1
overwrite_status=$?
set -e
[[ "$overwrite_status" -eq 4 ]]
after_hash="$(shasum -a 256 "$TMP_DIR/message.eml" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]]
rg -q '"code"[[:space:]]*:[[:space:]]*"MAIL_ERROR"' "$TMP_DIR/overwrite.json"

set +e
"$CLI" mail get --id "$selected_id" --content raw --output - --format json >"$TMP_DIR/stdout-conflict.bin" 2>&1
stdout_conflict_status=$?
set -e
[[ "$stdout_conflict_status" -eq 4 ]]
rg -q '"code"[[:space:]]*:[[:space:]]*"MAIL_ERROR"' "$TMP_DIR/stdout-conflict.bin"

echo "Mail content smoke test passed."
