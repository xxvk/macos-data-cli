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
run_expected_failure idempotency-conflict 2 "$CLI" contacts create --stdin --apply --idempotent --format json <<<'{"kind":"organization","externalID":"xvk-test-organizations-001","organizationName":"intentional-conflict"}'
run_expected_failure avatar-replace-missing-confirmation 2 "$CLI" contacts avatar replace --external-id xvk-test-contacts-001 --image "$ROOT_DIR/docs/development/icon1.png" --apply --format json

"$CLI" contacts avatar verify --external-id xvk-test-contacts-001 --format json >"$TMP_DIR/avatar-verify.out"
assert_contains "$TMP_DIR/avatar-verify.out" '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|verification_unknown|not_available)"'

"$CLI" contacts avatar replace --external-id xvk-test-contacts-001 --image "$ROOT_DIR/docs/development/icon1.png" --dry-run --format json >"$TMP_DIR/avatar-replace-dry-run.out"
assert_contains "$TMP_DIR/avatar-replace-dry-run.out" '"operation"[[:space:]]*:[[:space:]]*"avatar_replace"'

printf '%s' '{"kind":"person","externalID":"phonetic-contract-test-001","givenName":"顕","familyName":"上島","phoneticGivenName":"あきら","phoneticFamilyName":"かみじま"}' | "$CLI" contacts create --stdin --dry-run --format json >"$TMP_DIR/phonetic.out"
assert_contains "$TMP_DIR/phonetic.out" '"phoneticGivenName"[[:space:]]*:[[:space:]]*"あきら"'
assert_contains "$TMP_DIR/phonetic.out" '"phoneticFamilyName"[[:space:]]*:[[:space:]]*"かみじま"'

echo "CLI contract and negative-path tests passed."
