#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$CLI" ]]; then
  echo "CLI not found or not executable: $CLI" >&2
  echo "Run: swift build" >&2
  exit 1
fi

"$CLI" mail accounts --format json >"$TMP_DIR/accounts.json"
"$CLI" mail mailboxes --format json >"$TMP_DIR/mailboxes.json"
"$CLI" mail query --limit 2 --format json >"$TMP_DIR/query.json"

rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite"' "$TMP_DIR/accounts.json"
rg -q '"accounts"[[:space:]]*:' "$TMP_DIR/accounts.json"
rg -q '"backend"[[:space:]]*:[[:space:]]*"sqlite"' "$TMP_DIR/mailboxes.json"
rg -q '"mailboxes"[[:space:]]*:' "$TMP_DIR/mailboxes.json"
rg -q '"cacheState"[[:space:]]*:[[:space:]]*"metadata_only"' "$TMP_DIR/query.json"
rg -q '"truncated"[[:space:]]*:' "$TMP_DIR/query.json"
rg -q '"elapsedMs"[[:space:]]*:' "$TMP_DIR/query.json"
rg -q '"incomplete"[[:space:]]*:[[:space:]]*false' "$TMP_DIR/query.json"

if rg -qi 'Envelope Index|/Users/' "$TMP_DIR/accounts.json" "$TMP_DIR/mailboxes.json" "$TMP_DIR/query.json"; then
  echo "Mail output exposed a private local path." >&2
  exit 1
fi

echo "Mail metadata smoke test passed."
