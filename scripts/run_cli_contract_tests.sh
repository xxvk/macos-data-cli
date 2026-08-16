#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

[[ "${1:-}" == "--no-apply" || $# -eq 0 ]] || { echo "usage: $0 [--no-apply]" >&2; exit 64; }
[[ -x "$CLI" ]] || { echo "CLI not found: $CLI" >&2; exit 1; }

assert_json_error() {
  local name="$1" expected_exit="$2" expected_code="$3"
  shift 3
  local output="$TMP_DIR/$name.json"
  set +e
  "$@" >"$output" 2>&1
  local actual_exit=$?
  set -e
  [[ "$actual_exit" -eq "$expected_exit" ]] || { cat "$output" >&2; exit 1; }
  jq -e --arg code "$expected_code" '.ok == false and .contractVersion == "0.1" and .error.code == $code' "$output" >/dev/null
}

assert_adapter_error() {
  local name="$1" expected_exit="$2"
  shift 2
  local output="$TMP_DIR/$name.json"
  set +e
  "$@" >"$output" 2>&1
  local actual_exit=$?
  set -e
  [[ "$actual_exit" -eq "$expected_exit" ]] || { cat "$output" >&2; exit 1; }
  jq -e '.ok == false and .contractVersion == "0.1" and (.error.code | type == "string")' "$output" >/dev/null
}

"$CLI" --help >"$TMP_DIR/help.txt"
rg -q 'mpia METHOD "/command/path"' "$TMP_DIR/help.txt"
rg -q 'GET "/agent/manifest"' "$TMP_DIR/help.txt"
[[ "$("$CLI" --version)" == "$("$CLI" -v)" ]]

"$CLI" GET /agent/manifest >"$TMP_DIR/manifest.json"
jq -e '.ok == true and .data.cli.name == "mpia" and (.data.routes | length > 80)' "$TMP_DIR/manifest.json" >/dev/null
jq -e '[.data.routes[] | (.method + " " + .path)] | length == (unique | length)' "$TMP_DIR/manifest.json" >/dev/null
"$CLI" GET /agent/help | jq -e '.ok == true and (.data.usage | contains("METHOD \"/command/path\""))' >/dev/null

assert_json_error legacy 64 LEGACY_SYNTAX_REMOVED "$CLI" reminders edit
assert_json_error legacy-manifest 64 LEGACY_SYNTAX_REMOVED "$CLI" manifest
assert_json_error wrong-method 64 METHOD_NOT_ALLOWED "$CLI" POST /reminders/edit --params '{"id":"x"}' --body '{"title":"x"}' --dry-run
assert_json_error unknown-route 64 ROUTE_NOT_FOUND "$CLI" GET /unknown
assert_json_error trailing-slash 64 INVALID_REQUEST "$CLI" GET /reminders/query/
assert_json_error query-string 64 INVALID_REQUEST "$CLI" GET '/reminders/query?limit=1'
assert_json_error duplicate-option 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '{}' --params '{}'
assert_json_error malformed-params 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '{broken'
assert_json_error array-params 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '[]'
assert_json_error duplicate-json-key 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '{"limit":1,"limit":2}'
assert_json_error unknown-param 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '{"unknown":true}'
assert_json_error wrong-param-type 64 INVALID_REQUEST "$CLI" GET /messages/recent --params '{"limit":"1"}'
assert_json_error body-on-read 64 INVALID_REQUEST "$CLI" GET /messages/recent --body '{}'
assert_json_error missing-body 64 INVALID_REQUEST "$CLI" POST /reminders/create --dry-run
assert_json_error unknown-body-field 64 INVALID_REQUEST "$CLI" POST /reminders/create --body '{"title":"x","unknown":true}' --dry-run
assert_json_error safety-in-params 64 INVALID_REQUEST "$CLI" POST /reminders/create --params '{"apply":true}' --body '{"title":"x"}'
assert_json_error conflicting-mode 64 INVALID_REQUEST "$CLI" POST /reminders/create --body '{"title":"x"}' --dry-run --apply
assert_json_error confirm-without-apply 64 INVALID_REQUEST "$CLI" DELETE /reminders/delete --params '{"id":"x"}' --dry-run --confirm 'DELETE REMINDER'
assert_json_error missing-confirmation 64 INVALID_REQUEST "$CLI" DELETE /reminders/delete --params '{"id":"x"}' --apply
assert_json_error wrong-confirmation 64 INVALID_REQUEST "$CLI" DELETE /reminders/delete --params '{"id":"x"}' --apply --confirm 'DELETE EVENT'

# One bounded invocation per adapter. Permission/TCC failures are acceptable;
# parser or adapter output must remain a JSON envelope and no command may apply.
set +e
"$CLI" HEAD /contacts/count >"$TMP_DIR/contacts.json" 2>&1
"$CLI" OPTIONS /mail/doctor >"$TMP_DIR/mail.json" 2>&1
"$CLI" GET /calendar/query --params '{"start":"2026-08-16T00:00:00Z","end":"2026-08-17T00:00:00Z","limit":1}' >"$TMP_DIR/calendar.json" 2>&1
"$CLI" GET /reminders/query --params '{"limit":1}' >"$TMP_DIR/reminders.json" 2>&1
"$CLI" OPTIONS /photos/permission >"$TMP_DIR/photos.json" 2>&1
"$CLI" OPTIONS /notes/permission >"$TMP_DIR/notes.json" 2>&1
"$CLI" OPTIONS /shortcuts/permission >"$TMP_DIR/shortcuts.json" 2>&1
"$CLI" OPTIONS /safari/permission >"$TMP_DIR/safari.json" 2>&1
"$CLI" OPTIONS /messages/permission >"$TMP_DIR/messages.json" 2>&1
"$CLI" OPTIONS /phone-calls/permission >"$TMP_DIR/phone.json" 2>&1
set -e

for adapter in contacts mail calendar reminders photos notes shortcuts safari messages phone; do
  jq -e '.contractVersion == "0.1" and (.ok | type == "boolean")' "$TMP_DIR/$adapter.json" >/dev/null
done

# Body data must not be echoed by route-parser failures or diagnostics.
private_value='mpia-rest-private-body-sentinel'
assert_json_error redacted-body 64 INVALID_REQUEST "$CLI" POST /reminders/create \
  --body "{\"title\":\"$private_value\",\"unknown\":true}" --dry-run
if rg -q "$private_value" "$TMP_DIR/redacted-body.json"; then
  echo "REST parser leaked inline body content" >&2
  exit 1
fi

echo "REST CLI contract tests passed (no apply)."
