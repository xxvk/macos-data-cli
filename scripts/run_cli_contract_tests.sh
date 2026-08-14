#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
NO_APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-apply) NO_APPLY=true; shift ;;
    *) echo "usage: $0 [--no-apply]" >&2; exit 64 ;;
  esac
done

if [[ ! -x "$CLI" ]]; then
  echo "CLI not found or not executable: $CLI" >&2
  echo "Run: swift build" >&2
  exit 1
fi

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! rg -q "$pattern" "$file"; then
    echo "Expected pattern not found: $pattern" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_expected_failure() {
  local name="$1"
  local expected_code="$2"
  shift 2
  local output="$TMP_DIR/$name.out"
  set +e
  "$@" >"$output" 2>&1
  local actual_code=$?
  set -e
  if [[ "$actual_code" -ne "$expected_code" ]]; then
    echo "$name: expected exit $expected_code, got $actual_code" >&2
    cat "$output" >&2
    exit 1
  fi
  assert_contains "$output" '"ok"[[:space:]]*:[[:space:]]*false'
}

"$CLI" contacts count --format json >"$TMP_DIR/count.out"
assert_contains "$TMP_DIR/count.out" '"contractVersion"[[:space:]]*:[[:space:]]*"0.1"'
assert_contains "$TMP_DIR/count.out" '"ok"[[:space:]]*:[[:space:]]*true'

"$CLI" photos permission --format json >"$TMP_DIR/photos-permission.out"
assert_contains "$TMP_DIR/photos-permission.out" '"contractVersion"[[:space:]]*:[[:space:]]*"0.1"'
assert_contains "$TMP_DIR/photos-permission.out" '"access"[[:space:]]*:[[:space:]]*"(notDetermined|restricted|denied|limited|authorized)"'
assert_contains "$TMP_DIR/photos-permission.out" '"requested"[[:space:]]*:[[:space:]]*false'

set +e
printf '' | "$CLI" contacts create --stdin --dry-run --format json >"$TMP_DIR/empty-stdin.out" 2>&1
empty_code=$?
set -e
[[ "$empty_code" -eq 2 ]] || { cat "$TMP_DIR/empty-stdin.out" >&2; exit 1; }
assert_contains "$TMP_DIR/empty-stdin.out" '"CONTACTS_ERROR"'

set +e
printf '{broken-json' | "$CLI" contacts create --stdin --dry-run --format json >"$TMP_DIR/broken-json.out" 2>&1
broken_code=$?
set -e
[[ "$broken_code" -ne 0 ]] || { cat "$TMP_DIR/broken-json.out" >&2; exit 1; }
assert_contains "$TMP_DIR/broken-json.out" '"ok"[[:space:]]*:[[:space:]]*false'

run_expected_failure missing-input 64 "$CLI" contacts create --dry-run --format json
run_expected_failure missing-container 64 "$CLI" contacts count --container --format json
run_expected_failure unknown-container 2 "$CLI" contacts count --container DOES-NOT-EXIST --format json
for unsupported_mail_command in send draft reply forward move archive delete flag; do
  run_expected_failure "mail-$unsupported_mail_command-is-read-only" 64 "$CLI" mail "$unsupported_mail_command" --format json
done
if [[ "$NO_APPLY" != true ]]; then
  run_expected_failure idempotency-conflict 2 "$CLI" contacts create --stdin --apply --idempotent --format json <<<'{"kind":"organization","externalID":"xvk-test-organizations-001","organizationName":"intentional-conflict"}'
fi
run_expected_failure avatar-replace-missing-confirmation 2 "$CLI" contacts avatar replace --external-id xvk-test-contacts-001 --image "$ROOT_DIR/docs/development/icon1.png" --apply --format json
run_expected_failure calendar-query-missing-range 5 "$CLI" calendar query --format json
run_expected_failure calendar-query-invalid-range 5 "$CLI" calendar query --start 2026-08-15T00:00:00Z --end 2026-08-14T00:00:00Z --format json
run_expected_failure calendar-delete-missing-confirmation 5 "$CLI" calendar delete --id calevent_invalid --apply --format json
run_expected_failure calendar-delete-invalid-span 5 "$CLI" calendar delete --id calevent_invalid --dry-run --span all --format json
run_expected_failure reminders-delete-missing-confirmation 6 "$CLI" reminders delete --id reminder_invalid --apply --format json
run_expected_failure reminders-delete-wrong-confirmation 6 "$CLI" reminders delete --id reminder_invalid --apply --confirm "DELETE EVENT" --format json
run_expected_failure reminders-edit-missing-input 6 "$CLI" reminders edit --id reminder_invalid --dry-run --format json
run_expected_failure reminders-edit-missing-mode 6 "$CLI" reminders edit --id reminder_invalid --stdin --format json <<<'{"title":"Updated"}'
run_expected_failure reminders-edit-empty-patch 6 "$CLI" reminders edit --id reminder_invalid --stdin --dry-run --format json <<<'{}'
run_expected_failure reminders-edit-completion-is-separate 6 "$CLI" reminders edit --id reminder_invalid --stdin --dry-run --format json <<<'{"completed":true}'
run_expected_failure reminders-complete-missing-mode 6 "$CLI" reminders complete --id reminder_invalid --format json
run_expected_failure reminders-reopen-invalid-mode 6 "$CLI" reminders reopen --id reminder_invalid --apply --dry-run --format json
run_expected_failure photos-albums-invalid-limit 7 "$CLI" photos albums --limit 0 --format json
run_expected_failure photos-albums-invalid-kind 7 "$CLI" photos albums --kind unsupported --format json
run_expected_failure photos-query-missing-range 7 "$CLI" photos query --format json
run_expected_failure photos-query-invalid-favorite 7 "$CLI" photos query --start 2026-01-01T00:00:00Z --end 2026-01-02T00:00:00Z --favorite yes --format json
run_expected_failure photos-query-overwide-range 7 "$CLI" photos query --start 2025-01-01T00:00:00Z --end 2026-01-03T00:00:00Z --format json
run_expected_failure photos-get-missing-id 7 "$CLI" photos get --format json
run_expected_failure photos-export-missing-output 7 "$CLI" photos export --id photo_invalid --format json
run_expected_failure photos-export-invalid-variant 7 "$CLI" photos export --id photo_invalid --output /tmp/never-created --variant guessed --format json
run_expected_failure photos-export-stdout-forbidden 7 "$CLI" photos export --id photo_invalid --output - --format json

set +e
printf '' | "$CLI" calendar create --stdin --dry-run --format json >"$TMP_DIR/calendar-empty-stdin.out" 2>&1
calendar_empty_code=$?
set -e
[[ "$calendar_empty_code" -eq 5 ]] || { cat "$TMP_DIR/calendar-empty-stdin.out" >&2; exit 1; }
assert_contains "$TMP_DIR/calendar-empty-stdin.out" '"CALENDAR_INVALID_INPUT"'

"$CLI" contacts avatar verify --external-id xvk-test-contacts-001 --format json >"$TMP_DIR/avatar-verify.out"
assert_contains "$TMP_DIR/avatar-verify.out" '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|verification_unknown|not_available)"'

"$CLI" contacts avatar replace --external-id xvk-test-contacts-001 --image "$ROOT_DIR/docs/development/icon1.png" --dry-run --format json >"$TMP_DIR/avatar-replace-dry-run.out"
assert_contains "$TMP_DIR/avatar-replace-dry-run.out" '"operation"[[:space:]]*:[[:space:]]*"avatar_replace"'

printf '%s' '{"kind":"person","externalID":"phonetic-contract-test-001","givenName":"顕","familyName":"上島","phoneticGivenName":"あきら","phoneticFamilyName":"かみじま"}' | "$CLI" contacts create --stdin --dry-run --format json >"$TMP_DIR/phonetic.out"
assert_contains "$TMP_DIR/phonetic.out" '"phoneticGivenName"[[:space:]]*:[[:space:]]*"あきら"'
assert_contains "$TMP_DIR/phonetic.out" '"phoneticFamilyName"[[:space:]]*:[[:space:]]*"かみじま"'

echo "CLI contract and negative-path tests passed (noApply=$NO_APPLY)."
