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

"$CLI" calendar --help >"$TMP_DIR/help.txt"
rg -q 'Calendar commands:' "$TMP_DIR/help.txt"
rg -q 'query --start <iso8601>' "$TMP_DIR/help.txt"
rg -q 'DELETE EVENT' "$TMP_DIR/help.txt"
rg -q 'Attendees are returned by reads but are read-only' "$TMP_DIR/help.txt"
rg -q 'conflicts --start <iso8601>' "$TMP_DIR/help.txt"
rg -q '\[--idempotent\]' "$TMP_DIR/help.txt"

assert_failure missing-range 5 CALENDAR_INVALID_INPUT "$CLI" calendar query --format json
assert_failure reversed-range 5 CALENDAR_INVALID_DATE_RANGE "$CLI" calendar query \
  --start 2026-08-15T00:00:00Z --end 2026-08-14T00:00:00Z --format json
assert_failure excessive-range 5 CALENDAR_INVALID_DATE_RANGE "$CLI" calendar query \
  --start 2026-01-01T00:00:00Z --end 2028-01-01T00:00:00Z --format json
assert_failure missing-delete-confirmation 5 CALENDAR_INVALID_INPUT "$CLI" calendar delete \
  --id calevent_invalid --apply --format json
assert_failure invalid-recurrence-span 5 CALENDAR_INVALID_INPUT "$CLI" calendar delete \
  --id calevent_invalid --dry-run --span all --format json
assert_failure invalid-conflicts-option 5 CALENDAR_INVALID_INPUT "$CLI" calendar conflicts \
  --start 2026-01-01T00:00:00Z --end 2026-01-02T00:00:00Z --title private --format json
assert_failure duplicate-conflicts-range 5 CALENDAR_INVALID_INPUT "$CLI" calendar conflicts \
  --start 2026-01-01T00:00:00Z --start 2026-01-01T01:00:00Z --end 2026-01-02T00:00:00Z --format json
assert_failure invalid-all-day-timestamp 5 CALENDAR_INVALID_INPUT "$CLI" calendar create --stdin --dry-run --format json \
  <<<'{"title":"bad","allDay":true,"startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-02T00:00:00Z"}'
assert_failure mixed-all-day-date-formats 5 CALENDAR_INVALID_INPUT "$CLI" calendar create --stdin --dry-run --format json \
  <<<'{"title":"bad","allDay":true,"startDate":"2026-01-01","endDate":"2026-01-02T00:00:00Z"}'
assert_failure invalid-alarm 5 CALENDAR_INVALID_INPUT "$CLI" calendar create --stdin --dry-run --format json \
  <<<'{"title":"bad","startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-01T01:00:00Z","alarms":[{}]}'
assert_failure excessive-relative-alarm 5 CALENDAR_INVALID_INPUT "$CLI" calendar create --stdin --dry-run --format json \
  <<<'{"title":"bad","startDate":"2026-01-01T00:00:00Z","endDate":"2026-01-01T01:00:00Z","alarms":[{"relativeMinutes":525601}]}'
assert_failure idempotent-edit-is-unsupported 5 CALENDAR_INVALID_INPUT "$CLI" calendar edit \
  --id calevent_invalid --stdin --dry-run --idempotent --format json <<<'{"title":"bad"}'

set +e
printf '' | "$CLI" calendar create --stdin --dry-run --format json >"$TMP_DIR/empty.json" 2>&1
actual=$?
set -e
[[ "$actual" -eq 5 ]] || { cat "$TMP_DIR/empty.json" >&2; exit 1; }
rg -q '"CALENDAR_INVALID_INPUT"' "$TMP_DIR/empty.json"

set +e
printf '{broken-json' | "$CLI" calendar create --stdin --dry-run --format json >"$TMP_DIR/broken.json" 2>&1
actual=$?
set -e
[[ "$actual" -eq 5 ]] || { cat "$TMP_DIR/broken.json" >&2; exit 1; }
rg -q '"CALENDAR_INVALID_INPUT"' "$TMP_DIR/broken.json"

echo "Calendar CLI contract and negative-path tests passed."
