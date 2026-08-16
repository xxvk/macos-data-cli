#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

[[ -x "$CLI" ]] || { echo "CLI not found: $CLI" >&2; exit 1; }

assert_failure() {
  local name="$1"
  local code="$2"
  local machine_code="$3"
  shift 3
  local output="$TMP_DIR/$name.json"
  set +e
  "$@" >"$output" 2>&1
  local actual=$?
  set -e
  [[ "$actual" -eq "$code" ]] || { echo "$name: expected $code, got $actual" >&2; cat "$output" >&2; exit 1; }
  rg -q '"ok"[[:space:]]*:[[:space:]]*false' "$output" || { cat "$output" >&2; exit 1; }
  rg -q "\"$machine_code\"" "$output" || { cat "$output" >&2; exit 1; }
}

"$CLI" GET /agent/manifest >"$TMP_DIR/manifest.json"
jq -e '[.data.routes[] | select(.path | startswith("/calendar/"))] | length == 9' "$TMP_DIR/manifest.json" >/dev/null
jq -e '.data.routes[] | select(.path == "/calendar/delete") | .method == "DELETE" and .safety.confirmation == "DELETE EVENT"' "$TMP_DIR/manifest.json" >/dev/null
jq -e '.data.routes[] | select(.path == "/calendar/create") | .method == "POST" and .inputSchema == "CalendarEventInput"' "$TMP_DIR/manifest.json" >/dev/null

assert_failure missing-range 64 INVALID_REQUEST "$CLI" GET /calendar/query
assert_failure missing-delete-confirmation 64 INVALID_REQUEST "$CLI" DELETE /calendar/delete \
  --params '{"id":"calevent_invalid"}' --apply
assert_failure invalid-conflicts-option 64 INVALID_REQUEST "$CLI" GET /calendar/conflicts \
  --params '{"start":"2026-01-01T00:00:00Z","end":"2026-01-02T00:00:00Z","title":"private"}'
assert_failure idempotent-edit-is-unsupported 64 INVALID_REQUEST "$CLI" PATCH /calendar/edit \
  --params '{"id":"calevent_invalid","idempotent":true}' --body '{"title":"bad"}' --dry-run

set +e
"$CLI" POST /calendar/create --body '' --dry-run >"$TMP_DIR/empty.json" 2>&1
actual=$?
set -e
[[ "$actual" -eq 64 ]] || { cat "$TMP_DIR/empty.json" >&2; exit 1; }
rg -q '"INVALID_REQUEST"' "$TMP_DIR/empty.json"

set +e
"$CLI" POST /calendar/create --body '{broken-json' --dry-run >"$TMP_DIR/broken.json" 2>&1
actual=$?
set -e
[[ "$actual" -eq 64 ]] || { cat "$TMP_DIR/broken.json" >&2; exit 1; }
rg -q '"INVALID_REQUEST"' "$TMP_DIR/broken.json"

echo "Calendar CLI contract and negative-path tests passed."
