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

"$CLI" notes permission --format json >"$TMP_DIR/notes-permission.out"
assert_contains "$TMP_DIR/notes-permission.out" '"contractVersion"[[:space:]]*:[[:space:]]*"0.1"'
assert_contains "$TMP_DIR/notes-permission.out" '"access"[[:space:]]*:[[:space:]]*"(available|denied|requiresConsent|targetNotRunning|targetUnavailable|unknown)"'
assert_contains "$TMP_DIR/notes-permission.out" '"requested"[[:space:]]*:[[:space:]]*false'

"$CLI" shortcuts permission --format json >"$TMP_DIR/shortcuts-permission.out"
assert_contains "$TMP_DIR/shortcuts-permission.out" '"contractVersion"[[:space:]]*:[[:space:]]*"0.1"'
assert_contains "$TMP_DIR/shortcuts-permission.out" '"access"[[:space:]]*:[[:space:]]*"(available|denied|requiresConsent|targetNotRunning|targetUnavailable|unknown)"'
assert_contains "$TMP_DIR/shortcuts-permission.out" '"requested"[[:space:]]*:[[:space:]]*false'

"$CLI" notes --help >"$TMP_DIR/notes-help.out"
assert_contains "$TMP_DIR/notes-help.out" 'Notes 0\.6 read commands and guarded 0\.6\.1/0\.6\.2 writes'

"$CLI" shortcuts --help >"$TMP_DIR/shortcuts-help.out"
assert_contains "$TMP_DIR/shortcuts-help.out" 'Shortcuts 0\.7 commands'
assert_contains "$TMP_DIR/shortcuts-help.out" 'MOVE SHORTCUT'
assert_contains "$TMP_DIR/shortcuts-help.out" 'RUN SHORTCUT'
assert_contains "$TMP_DIR/shortcuts-help.out" 'author validate'
assert_contains "$TMP_DIR/shortcuts-help.out" 'author build'
assert_contains "$TMP_DIR/shortcuts-help.out" 'never uses HubSign'
assert_contains "$TMP_DIR/shortcuts-help.out" 'CREATE MANAGED SHORTCUT'
assert_contains "$TMP_DIR/shortcuts-help.out" 'UPDATE MANAGED SHORTCUT'
assert_contains "$TMP_DIR/shortcuts-help.out" 'FORGET MANAGED SHORTCUT'

"$CLI" --help >"$TMP_DIR/global-help.out"
assert_contains "$TMP_DIR/global-help.out" '7 Photos error, 8 Notes error, 9 Shortcuts error'

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
run_expected_failure notes-folders-invalid-limit 8 "$CLI" notes folders --limit 0 --format json
run_expected_failure notes-folders-missing-value 8 "$CLI" notes folders --account-id --format json
run_expected_failure notes-folder-create-missing-input 8 "$CLI" notes folder create --dry-run --format json
run_expected_failure notes-folder-create-missing-parent 8 "$CLI" notes folder create --stdin --dry-run --format json <<<'{"name":"Projects"}'
run_expected_failure notes-folder-create-unknown-field 8 "$CLI" notes folder create --stdin --dry-run --format json <<<'{"name":"Projects","parentFolderID":null,"unknown":true}'
run_expected_failure notes-folder-rename-missing-id 8 "$CLI" notes folder rename --stdin --dry-run --format json <<<'{"name":"Projects","expectedNameSHA256":"0000000000000000000000000000000000000000000000000000000000000000"}'
run_expected_failure notes-folder-rename-invalid-hash 8 "$CLI" notes folder rename --id notesfolder_invalid --stdin --dry-run --format json <<<'{"name":"Projects","expectedNameSHA256":"bad"}'
run_expected_failure notes-folder-delete-missing-confirmation 8 "$CLI" notes folder delete --id notesfolder_invalid --stdin --apply --format json <<<'{"expectedParentFolderID":null,"expectedNameSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
run_expected_failure notes-folder-delete-wrong-confirmation 8 "$CLI" notes folder delete --id notesfolder_invalid --stdin --apply --confirm "DELETE NOTES FOLDER" --format json <<<'{"expectedParentFolderID":null,"expectedNameSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
run_expected_failure notes-folder-delete-unknown-field 8 "$CLI" notes folder delete --id notesfolder_invalid --stdin --dry-run --format json <<<'{"expectedParentFolderID":null,"expectedNameSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","unknown":true}'
run_expected_failure notes-folder-delete-apply-unsupported 8 "$CLI" notes folder delete --id notesfolder_invalid --stdin --apply --confirm "DELETE EMPTY NOTES FOLDER" --format json <<<'{"expectedParentFolderID":null,"expectedNameSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
assert_contains "$TMP_DIR/notes-folder-delete-apply-unsupported.out" 'NOTES_FOLDER_DELETE_UNSUPPORTED'
run_expected_failure notes-folder-move-missing-expected-parent 8 "$CLI" notes folder move --id notesfolder_invalid --stdin --dry-run --format json <<<'{"destinationParentFolderID":null,"expectedNameSHA256":"0000000000000000000000000000000000000000000000000000000000000000"}'
run_expected_failure notes-folder-move-conflicting-mode 8 "$CLI" notes folder move --id notesfolder_invalid --stdin --dry-run --apply --format json <<<'{"destinationParentFolderID":null,"expectedParentFolderID":null,"expectedNameSHA256":"0000000000000000000000000000000000000000000000000000000000000000"}'
run_expected_failure notes-folder-move-apply-unsupported 8 "$CLI" notes folder move --id notesfolder_invalid --stdin --apply --format json <<<'{"destinationParentFolderID":null,"expectedParentFolderID":null,"expectedNameSHA256":"0000000000000000000000000000000000000000000000000000000000000000"}'
assert_contains "$TMP_DIR/notes-folder-move-apply-unsupported.out" 'NOTES_FOLDER_MOVE_UNSUPPORTED'
run_expected_failure notes-query-invalid-limit 8 "$CLI" notes query --limit 0 --format json
run_expected_failure notes-query-invalid-date 8 "$CLI" notes query --modified-after not-a-date --format json
run_expected_failure notes-query-missing-value 8 "$CLI" notes query --title --format json
run_expected_failure notes-get-missing-id 8 "$CLI" notes get --format json
run_expected_failure notes-get-invalid-body 8 "$CLI" notes get --id note_invalid --body markdown --format json
run_expected_failure notes-get-duplicate-attachments 8 "$CLI" notes get --id note_invalid --include-attachments --include-attachments --format json
run_expected_failure notes-create-missing-input 8 "$CLI" notes create --dry-run --format json
run_expected_failure notes-create-conflicting-mode 8 "$CLI" notes create --stdin --dry-run --apply --format json <<<'{"folderID":"x","title":"x","bodyFormat":"plaintext","body":""}'
run_expected_failure notes-create-unknown-field 8 "$CLI" notes create --stdin --dry-run --format json <<<'{"folderID":"x","title":"x","bodyFormat":"plaintext","body":"","unknown":true}'
run_expected_failure notes-rename-missing-id 8 "$CLI" notes rename --stdin --dry-run --format json <<<'{"title":"x","expectedModificationDate":"2026-08-14T00:00:00Z"}'
run_expected_failure notes-move-missing-input 8 "$CLI" notes move --id note_invalid --dry-run --format json
run_expected_failure notes-delete-missing-id 8 "$CLI" notes delete --stdin --dry-run --format json <<<'{"expectedModificationDate":"2026-08-14T00:00:00Z"}'
run_expected_failure notes-delete-missing-confirmation 8 "$CLI" notes delete --id note_invalid --stdin --apply --format json <<<'{"expectedModificationDate":"2026-08-14T00:00:00Z"}'
run_expected_failure notes-delete-wrong-confirmation 8 "$CLI" notes delete --id note_invalid --stdin --apply --confirm "DELETE NOTES" --format json <<<'{"expectedModificationDate":"2026-08-14T00:00:00Z"}'
run_expected_failure notes-delete-valid-confirmation-invalid-id 8 "$CLI" notes delete --id note_invalid --stdin --apply --confirm "DELETE NOTE" --format json <<<'{"expectedModificationDate":"2026-08-14T00:00:00Z"}'
run_expected_failure notes-delete-unknown-field 8 "$CLI" notes delete --id note_invalid --stdin --dry-run --format json <<<'{"expectedModificationDate":"2026-08-14T00:00:00Z","unknown":true}'
run_expected_failure notes-edit-body-missing-id 8 "$CLI" notes edit-body --stdin --dry-run --format json <<<'{"bodyFormat":"plaintext","body":"x","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"0000000000000000000000000000000000000000000000000000000000000000"}'
run_expected_failure notes-edit-body-unknown-field 8 "$CLI" notes edit-body --id note_invalid --stdin --dry-run --format json <<<'{"bodyFormat":"plaintext","body":"x","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"0000000000000000000000000000000000000000000000000000000000000000","unknown":true}'
run_expected_failure notes-edit-body-invalid-hash 8 "$CLI" notes edit-body --id note_invalid --stdin --dry-run --format json <<<'{"bodyFormat":"plaintext","body":"x","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"bad"}'
run_expected_failure notes-bind-wrong-confirmation 8 "$CLI" notes write-account bind --account-id notesaccount_invalid --apply --confirm "BIND NOTES" --format json
run_expected_failure notes-clear-wrong-confirmation 8 "$CLI" notes write-account clear --apply --confirm "CLEAR NOTES" --format json
run_expected_failure shortcuts-list-invalid-limit 9 "$CLI" shortcuts list --limit 0 --format json
run_expected_failure shortcuts-get-invalid-id 9 "$CLI" shortcuts get --id shortcut_invalid --format json
run_expected_failure shortcuts-run-missing-apply 9 "$CLI" shortcuts run --id shortcut_invalid --format json
run_expected_failure shortcuts-run-wrong-confirmation 9 "$CLI" shortcuts run --id shortcut_invalid --apply --confirm "RUN" --format json
run_expected_failure shortcuts-run-invalid-timeout 9 "$CLI" shortcuts run --id shortcut_invalid --timeout 0 --apply --confirm "RUN SHORTCUT" --format json
run_expected_failure shortcuts-move-missing-confirmation 9 "$CLI" shortcuts move --id shortcut_invalid --destination-folder-id shortcutfolder_invalid --apply --format json
run_expected_failure shortcuts-move-conflicting-mode 9 "$CLI" shortcuts move --id shortcut_invalid --destination-folder-id shortcutfolder_invalid --dry-run --apply --format json
run_expected_failure shortcuts-author-validate-missing-source 9 "$CLI" shortcuts author validate --format json
run_expected_failure shortcuts-author-validate-wrong-extension 9 "$CLI" shortcuts author validate --source "$TMP_DIR/source.txt" --format json
run_expected_failure shortcuts-author-build-missing-output 9 "$CLI" shortcuts author build --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --format json
run_expected_failure shortcuts-author-build-invalid-signing-mode 9 "$CLI" shortcuts author build --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --output "$TMP_DIR/out.shortcut" --signing-mode remote --format json
run_expected_failure shortcuts-create-missing-source 9 "$CLI" shortcuts create --dry-run --format json
run_expected_failure shortcuts-create-conflicting-mode 9 "$CLI" shortcuts create --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --dry-run --apply --format json
run_expected_failure shortcuts-create-apply-missing-confirmation 9 "$CLI" shortcuts create --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --apply --format json
run_expected_failure shortcuts-create-apply-wrong-confirmation 9 "$CLI" shortcuts create --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --apply --confirm "CREATE SHORTCUT" --format json
run_expected_failure shortcuts-create-dry-run-rejects-confirmation 9 "$CLI" shortcuts create --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --dry-run --confirm "CREATE MANAGED SHORTCUT" --format json
run_expected_failure shortcuts-update-missing-strategy 9 "$CLI" shortcuts update --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --expected-source-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --dry-run --format json
run_expected_failure shortcuts-update-conflicting-mode 9 "$CLI" shortcuts update --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --expected-source-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --strategy retain-old --dry-run --apply --format json
run_expected_failure shortcuts-update-apply-missing-confirmation 9 "$CLI" shortcuts update --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --expected-source-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --strategy retain-old --apply --format json
run_expected_failure shortcuts-update-wrong-confirmation 9 "$CLI" shortcuts update --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --expected-source-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --strategy replace --apply --confirm "UPDATE SHORTCUT" --format json
run_expected_failure shortcuts-update-unmanaged 9 "$CLI" shortcuts update --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --source "$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri" --expected-source-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --strategy retain-old --dry-run --format json
assert_contains "$TMP_DIR/shortcuts-update-unmanaged.out" 'SHORTCUTS_AUTHOR_MANAGED_ONLY'
"$CLI" shortcuts managed list --format json >"$TMP_DIR/shortcuts-managed-list.out"
assert_contains "$TMP_DIR/shortcuts-managed-list.out" '"ok"[[:space:]]*:[[:space:]]*true'
run_expected_failure shortcuts-managed-forget-missing-confirmation 9 "$CLI" shortcuts managed forget --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --apply --format json
run_expected_failure shortcuts-managed-forget-unmanaged 9 "$CLI" shortcuts managed forget --id shortcut_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --dry-run --format json

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
