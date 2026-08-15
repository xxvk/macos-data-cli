#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
TMP_DIR="$(mktemp -d)"
TITLE="mpia disposable reminder $(date -u +%Y%m%dT%H%M%SZ)-$$"
UPDATED_TITLE="$TITLE updated"
REMINDER_ID=""

usage() {
  echo 'usage: run_local_reminders_integration.sh --with-writes --confirm "REMINDERS CRUD TEST"' >&2
  exit 64
}

cleanup() {
  if [[ -n "$REMINDER_ID" ]]; then
    "$CLI" reminders delete --id "$REMINDER_ID" --apply --confirm "DELETE REMINDER" --format json >/dev/null 2>&1 || true
  fi
  if [[ -x "$CLI" ]] && command -v jq >/dev/null; then
    for cleanup_title in "$TITLE" "$UPDATED_TITLE"; do
      "$CLI" reminders query --status all --title "$cleanup_title" --limit 20 --format json 2>/dev/null |
        jq -r --arg title "$cleanup_title" '.data.items[] | select(.title == $title) | .id' 2>/dev/null |
        while IFS= read -r id; do
          [[ -n "$id" ]] || continue
          "$CLI" reminders delete --id "$id" --apply --confirm "DELETE REMINDER" --format json >/dev/null 2>&1 || true
        done
    done
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

[[ $# -eq 3 && "$1" == "--with-writes" && "$2" == "--confirm" && "$3" == "REMINDERS CRUD TEST" ]] || usage
[[ -x "$CLI" ]] || { echo "CLI not found or not executable: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Reminders integration requires jq." >&2; exit 1; }

jq -n --arg title "$TITLE" '{title:$title, priority:"none", alarms:[], recurrenceRules:[]}' >"$TMP_DIR/input.json"

"$CLI" reminders create --input "$TMP_DIR/input.json" --dry-run --format json >"$TMP_DIR/preview.json"
jq -e --arg title "$TITLE" '.ok == true and .data.operation == "create_preview" and .data.reminder.title == $title' "$TMP_DIR/preview.json" >/dev/null

"$CLI" reminders create --input "$TMP_DIR/input.json" --apply --idempotent --format json >"$TMP_DIR/created.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/created.json")"
jq -e '.ok == true and .data.created == true and (.data.verification == "readback_confirmed" or .data.verification == "save_accepted_readback_pending")' "$TMP_DIR/created.json" >/dev/null

"$CLI" reminders get --id "$REMINDER_ID" --format json >"$TMP_DIR/readback.json"
jq -e --arg title "$TITLE" '.ok == true and .data.title == $title' "$TMP_DIR/readback.json" >/dev/null

jq -n --arg title "$UPDATED_TITLE" '{title:$title, priority:"low", notes:null}' >"$TMP_DIR/patch.json"
"$CLI" reminders edit --id "$REMINDER_ID" --input "$TMP_DIR/patch.json" --dry-run --format json >"$TMP_DIR/edit-preview.json"
jq -e --arg before "$TITLE" --arg after "$UPDATED_TITLE" '.ok == true and .data.operation == "update_preview" and .data.before.title == $before and .data.after.title == $after and .data.after.priority == "low"' "$TMP_DIR/edit-preview.json" >/dev/null

"$CLI" reminders edit --id "$REMINDER_ID" --input "$TMP_DIR/patch.json" --apply --format json >"$TMP_DIR/updated.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/updated.json")"
jq -e --arg title "$UPDATED_TITLE" '.ok == true and .data.operation == "updated" and .data.reminder.title == $title and .data.reminder.priority == "low" and (.data.verification == "readback_confirmed" or .data.verification == "save_accepted_readback_pending")' "$TMP_DIR/updated.json" >/dev/null

"$CLI" reminders get --id "$REMINDER_ID" --format json >"$TMP_DIR/edit-readback.json"
jq -e --arg title "$UPDATED_TITLE" '.ok == true and .data.title == $title and .data.priority == "low"' "$TMP_DIR/edit-readback.json" >/dev/null

"$CLI" reminders complete --id "$REMINDER_ID" --dry-run --format json >"$TMP_DIR/complete-preview.json"
jq -e '.ok == true and .data.operation == "complete_preview" and .data.before.completed == false and .data.after.completed == true' "$TMP_DIR/complete-preview.json" >/dev/null

"$CLI" reminders complete --id "$REMINDER_ID" --apply --format json >"$TMP_DIR/completed.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/completed.json")"
jq -e '.ok == true and .data.operation == "completed" and .data.changed == true and .data.reminder.completed == true' "$TMP_DIR/completed.json" >/dev/null

"$CLI" reminders complete --id "$REMINDER_ID" --apply --format json >"$TMP_DIR/already-completed.json"
jq -e '.ok == true and .data.operation == "already_completed" and .data.changed == false' "$TMP_DIR/already-completed.json" >/dev/null

"$CLI" reminders reopen --id "$REMINDER_ID" --dry-run --format json >"$TMP_DIR/reopen-preview.json"
jq -e '.ok == true and .data.operation == "reopen_preview" and .data.before.completed == true and .data.after.completed == false' "$TMP_DIR/reopen-preview.json" >/dev/null

"$CLI" reminders reopen --id "$REMINDER_ID" --apply --format json >"$TMP_DIR/reopened.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/reopened.json")"
jq -e '.ok == true and .data.operation == "reopened" and .data.changed == true and .data.reminder.completed == false and .data.reminder.completionDate == null' "$TMP_DIR/reopened.json" >/dev/null

"$CLI" reminders reopen --id "$REMINDER_ID" --apply --format json >"$TMP_DIR/already-incomplete.json"
jq -e '.ok == true and .data.operation == "already_incomplete" and .data.changed == false' "$TMP_DIR/already-incomplete.json" >/dev/null

"$CLI" reminders delete --id "$REMINDER_ID" --dry-run --format json >"$TMP_DIR/delete-preview.json"
jq -e '.ok == true and .data.operation == "delete_preview" and .data.deleted == false and .data.verification == "preview"' "$TMP_DIR/delete-preview.json" >/dev/null

"$CLI" reminders delete --id "$REMINDER_ID" --apply --confirm "DELETE REMINDER" --format json >"$TMP_DIR/deleted.json"
jq -e '.ok == true and .data.operation == "deleted" and .data.deleted == true and (.data.verification == "absence_confirmed" or .data.verification == "remove_accepted_readback_pending")' "$TMP_DIR/deleted.json" >/dev/null

set +e
"$CLI" reminders get --id "$REMINDER_ID" --format json >"$TMP_DIR/absent.json" 2>&1
absent_status=$?
set -e
[[ $absent_status -eq 6 ]] || { cat "$TMP_DIR/absent.json" >&2; exit 1; }
jq -e '.ok == false and .error.code == "REMINDERS_NOT_FOUND"' "$TMP_DIR/absent.json" >/dev/null
REMINDER_ID=""

remaining="$("$CLI" reminders query --status all --title "$UPDATED_TITLE" --limit 20 --format json)"
printf '%s' "$remaining" | jq -e --arg title "$UPDATED_TITLE" '[.data.items[] | select(.title == $title)] | length == 0' >/dev/null

echo "Reminders disposable create/get/edit/complete/reopen/delete integration passed; final matching count is zero."
