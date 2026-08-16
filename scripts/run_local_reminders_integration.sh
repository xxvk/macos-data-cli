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
    "$CLI" DELETE /reminders/delete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply --confirm "DELETE REMINDER" >/dev/null 2>&1 || true
  fi
  if [[ -x "$CLI" ]] && command -v jq >/dev/null; then
    for cleanup_title in "$TITLE" "$UPDATED_TITLE"; do
      "$CLI" GET /reminders/query --params "$(jq -cn --arg title "$cleanup_title" '{status:"all",title:$title,limit:20}')" 2>/dev/null |
        jq -r --arg title "$cleanup_title" '.data.items[] | select(.title == $title) | .id' 2>/dev/null |
        while IFS= read -r id; do
          [[ -n "$id" ]] || continue
          "$CLI" DELETE /reminders/delete --params "$(jq -cn --arg id "$id" '{id:$id}')" --apply --confirm "DELETE REMINDER" >/dev/null 2>&1 || true
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

"$CLI" POST /reminders/create --body "$(jq -c . "$TMP_DIR/input.json")" --dry-run >"$TMP_DIR/preview.json"
jq -e --arg title "$TITLE" '.ok == true and .data.operation == "create_preview" and .data.reminder.title == $title' "$TMP_DIR/preview.json" >/dev/null

"$CLI" POST /reminders/create --params '{"idempotent":true}' --body "$(jq -c . "$TMP_DIR/input.json")" --apply >"$TMP_DIR/created.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/created.json")"
jq -e '.ok == true and .data.created == true and (.data.verification == "readback_confirmed" or .data.verification == "save_accepted_readback_pending")' "$TMP_DIR/created.json" >/dev/null

"$CLI" GET /reminders/get --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" >"$TMP_DIR/readback.json"
jq -e --arg title "$TITLE" '.ok == true and .data.title == $title' "$TMP_DIR/readback.json" >/dev/null

jq -n --arg title "$UPDATED_TITLE" '{title:$title, priority:"low", notes:null}' >"$TMP_DIR/patch.json"
"$CLI" PATCH /reminders/edit --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --body "$(jq -c . "$TMP_DIR/patch.json")" --dry-run >"$TMP_DIR/edit-preview.json"
jq -e --arg before "$TITLE" --arg after "$UPDATED_TITLE" '.ok == true and .data.operation == "update_preview" and .data.before.title == $before and .data.after.title == $after and .data.after.priority == "low"' "$TMP_DIR/edit-preview.json" >/dev/null

"$CLI" PATCH /reminders/edit --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --body "$(jq -c . "$TMP_DIR/patch.json")" --apply >"$TMP_DIR/updated.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/updated.json")"
jq -e --arg title "$UPDATED_TITLE" '.ok == true and .data.operation == "updated" and .data.reminder.title == $title and .data.reminder.priority == "low" and (.data.verification == "readback_confirmed" or .data.verification == "save_accepted_readback_pending")' "$TMP_DIR/updated.json" >/dev/null

"$CLI" GET /reminders/get --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" >"$TMP_DIR/edit-readback.json"
jq -e --arg title "$UPDATED_TITLE" '.ok == true and .data.title == $title and .data.priority == "low"' "$TMP_DIR/edit-readback.json" >/dev/null

"$CLI" POST /reminders/complete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --dry-run >"$TMP_DIR/complete-preview.json"
jq -e '.ok == true and .data.operation == "complete_preview" and .data.before.completed == false and .data.after.completed == true' "$TMP_DIR/complete-preview.json" >/dev/null

"$CLI" POST /reminders/complete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply >"$TMP_DIR/completed.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/completed.json")"
jq -e '.ok == true and .data.operation == "completed" and .data.changed == true and .data.reminder.completed == true' "$TMP_DIR/completed.json" >/dev/null

"$CLI" POST /reminders/complete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply >"$TMP_DIR/already-completed.json"
jq -e '.ok == true and .data.operation == "already_completed" and .data.changed == false' "$TMP_DIR/already-completed.json" >/dev/null

"$CLI" POST /reminders/reopen --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --dry-run >"$TMP_DIR/reopen-preview.json"
jq -e '.ok == true and .data.operation == "reopen_preview" and .data.before.completed == true and .data.after.completed == false' "$TMP_DIR/reopen-preview.json" >/dev/null

"$CLI" POST /reminders/reopen --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply >"$TMP_DIR/reopened.json"
REMINDER_ID="$(jq -er '.data.reminder.id' "$TMP_DIR/reopened.json")"
jq -e '.ok == true and .data.operation == "reopened" and .data.changed == true and .data.reminder.completed == false and .data.reminder.completionDate == null' "$TMP_DIR/reopened.json" >/dev/null

"$CLI" POST /reminders/reopen --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply >"$TMP_DIR/already-incomplete.json"
jq -e '.ok == true and .data.operation == "already_incomplete" and .data.changed == false' "$TMP_DIR/already-incomplete.json" >/dev/null

"$CLI" DELETE /reminders/delete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --dry-run >"$TMP_DIR/delete-preview.json"
jq -e '.ok == true and .data.operation == "delete_preview" and .data.deleted == false and .data.verification == "preview"' "$TMP_DIR/delete-preview.json" >/dev/null

"$CLI" DELETE /reminders/delete --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" --apply --confirm "DELETE REMINDER" >"$TMP_DIR/deleted.json"
jq -e '.ok == true and .data.operation == "deleted" and .data.deleted == true and (.data.verification == "absence_confirmed" or .data.verification == "remove_accepted_readback_pending")' "$TMP_DIR/deleted.json" >/dev/null

set +e
"$CLI" GET /reminders/get --params "$(jq -cn --arg id "$REMINDER_ID" '{id:$id}')" >"$TMP_DIR/absent.json" 2>&1
absent_status=$?
set -e
[[ $absent_status -eq 6 ]] || { cat "$TMP_DIR/absent.json" >&2; exit 1; }
jq -e '.ok == false and .error.code == "REMINDERS_NOT_FOUND"' "$TMP_DIR/absent.json" >/dev/null
REMINDER_ID=""

remaining="$("$CLI" GET /reminders/query --params "$(jq -cn --arg title "$UPDATED_TITLE" '{status:"all",title:$title,limit:20}')")"
printf '%s' "$remaining" | jq -e --arg title "$UPDATED_TITLE" '[.data.items[] | select(.title == $title)] | length == 0' >/dev/null

echo "Reminders disposable create/get/edit/complete/reopen/delete integration passed; final matching count is zero."
