#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$CLI" ]]; then
  echo "CLI not found or not executable. Run: swift build" >&2
  exit 1
fi

"$CLI" GET /mail/query --params '{"limit":50}' >"$TMP_DIR/query.json"

selected_id=""
for index in $(seq 0 49); do
  id="$(plutil -extract "data.messages.$index.id" raw -o - "$TMP_DIR/query.json" 2>/dev/null || true)"
  [[ -n "$id" ]] || break
  params="$(jq -cn --arg id "$id" '{id:$id,content:"metadata"}')"
  "$CLI" GET /mail/get --params "$params" >"$TMP_DIR/metadata.json"
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

params="$(jq -cn --arg id "$selected_id" '{id:$id,content:"text"}')"
"$CLI" GET /mail/get --params "$params" >"$TMP_DIR/text.json"
rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite_emlx"' "$TMP_DIR/text.json"
rg -q '"cacheState"[[:space:]]*:[[:space:]]*"complete"' "$TMP_DIR/text.json"
rg -q '"incomplete"[[:space:]]*:[[:space:]]*false' "$TMP_DIR/text.json"

params="$(jq -cn --arg id "$selected_id" --arg output "$TMP_DIR/message.eml" '{id:$id,content:"raw",output:$output}')"
"$CLI" GET /mail/get --params "$params" >"$TMP_DIR/raw-result.json"
test -s "$TMP_DIR/message.eml"
rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite_emlx"' "$TMP_DIR/raw-result.json"
rg -q '"output"[[:space:]]*:[[:space:]]*"file"' "$TMP_DIR/raw-result.json"

before_hash="$(shasum -a 256 "$TMP_DIR/message.eml" | awk '{print $1}')"
set +e
"$CLI" GET /mail/get --params "$params" >"$TMP_DIR/overwrite.json" 2>&1
overwrite_status=$?
set -e
[[ "$overwrite_status" -eq 4 ]]
after_hash="$(shasum -a 256 "$TMP_DIR/message.eml" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]]
rg -q '"code"[[:space:]]*:[[:space:]]*"MAIL_ERROR"' "$TMP_DIR/overwrite.json"

set +e
stdout_params="$(jq -cn --arg id "$selected_id" '{id:$id,content:"raw",output:"-"}')"
"$CLI" GET /mail/get --params "$stdout_params" >"$TMP_DIR/stdout-conflict.bin" 2>&1
stdout_conflict_status=$?
set -e
[[ "$stdout_conflict_status" -eq 4 ]]
rg -q '"code"[[:space:]]*:[[:space:]]*"MAIL_ERROR"' "$TMP_DIR/stdout-conflict.bin"

echo "Mail content smoke test passed."
