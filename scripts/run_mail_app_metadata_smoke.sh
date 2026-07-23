#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/.build/debug/macos-data.app"
CLI="$APP/Contents/MacOS/macos-data"

if [[ ! -d "$APP" ]]; then
  echo "signed Debug app is missing; run bash scripts/build_debug_app.sh" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d /private/tmp/macos-data-mail-app-metadata.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_cli() {
  local output="$1"
  shift
  set +e
  launchctl asuser "$(id -u)" /usr/bin/env \
    MACOS_DATA_MAIL_FORCE_APP_FALLBACK=1 \
    "$CLI" "$@" >"$output" 2>"$TEMP_DIR/stderr.json"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    local code
    code="$(/usr/bin/jq -r '.error.code // "invalid_error_response"' "$TEMP_DIR/stderr.json" 2>/dev/null || echo invalid_error_response)"
    echo "Mail.app metadata fallback smoke failed: code=$code processExit=$status" >&2
    return "$status"
  fi
}

validate_json() {
  local file="$1"
  local expression="$2"
  if ! /usr/bin/jq -e "$expression" "$file" >/dev/null 2>&1; then
    local code output_bytes error_bytes
    code="$(/usr/bin/jq -r '.error.code // "invalid_response"' "$TEMP_DIR/stderr.json" 2>/dev/null || echo invalid_response)"
    output_bytes="$(wc -c < "$file" | tr -d ' ')"
    error_bytes="$(wc -c < "$TEMP_DIR/stderr.json" | tr -d ' ')"
    echo "Mail.app metadata fallback smoke validation failed: code=$code stdoutBytes=$output_bytes stderrBytes=$error_bytes" >&2
    return 1
  fi
}

run_cli "$TEMP_DIR/accounts.json" mail accounts --format json
validate_json "$TEMP_DIR/accounts.json" '.ok == true and .data.backend == "mail_app"'

run_cli "$TEMP_DIR/mailboxes.json" mail mailboxes --format json
validate_json "$TEMP_DIR/mailboxes.json" '.ok == true and .data.backend == "mail_app"'

run_cli "$TEMP_DIR/query.json" mail query --limit 1 --format json
validate_json "$TEMP_DIR/query.json" '.ok == true and .data.backend == "mail_app" and .data.incomplete == true'

message_count="$(/usr/bin/jq -r '.data.messages | length' "$TEMP_DIR/query.json")"
if [[ "$message_count" -gt 0 ]]; then
  message_id="$(/usr/bin/jq -r '.data.messages[0].id' "$TEMP_DIR/query.json")"
  run_cli "$TEMP_DIR/get.json" mail get --id "$message_id" --format json
  validate_json "$TEMP_DIR/get.json" '.ok == true and .data.backend == "mail_app" and .data.message.idScope == "mail_app_local"'
fi

account_count="$(/usr/bin/jq -r '.data.accounts | length' "$TEMP_DIR/accounts.json")"
mailbox_count="$(/usr/bin/jq -r '.data.mailboxes | length' "$TEMP_DIR/mailboxes.json")"
echo "Mail.app metadata fallback smoke passed: accounts=$account_count mailboxes=$mailbox_count messages=$message_count"
