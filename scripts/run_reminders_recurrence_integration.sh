#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data.app/Contents/MacOS/macos-data}"
TMP_DIR="$(mktemp -d)"
TITLE="macos-data recurring reminder $(date -u +%Y%m%dT%H%M%SZ)-$$"

usage() {
  echo 'usage: run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"' >&2
  exit 64
}

cleanup() {
  if [[ -x "$CLI" ]] && command -v jq >/dev/null; then
    for _ in 1 2 3 4; do
      ids="$("$CLI" reminders query --status all --title "$TITLE" --limit 20 --format json 2>/dev/null |
        jq -r --arg title "$TITLE" '.data.items[] | select(.title == $title) | .id' 2>/dev/null || true)"
      [[ -n "$ids" ]] || break
      while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        "$CLI" reminders delete --id "$id" --apply --confirm "DELETE REMINDER" --format json >/dev/null 2>&1 || true
      done <<<"$ids"
    done
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

[[ $# -eq 2 && "$1" == "--confirm" && "$2" == "REMINDERS RECURRENCE TEST" ]] || usage
[[ -x "$CLI" ]] || { echo "CLI not found or not executable: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Reminders recurrence integration requires jq." >&2; exit 1; }

start_date="$(date +%Y-%m-%d)"
jq -n --arg title "$TITLE" --arg due "$start_date" '{
  title:$title,
  due:{value:$due,timeZone:null,hasTime:false,floating:true},
  recurrenceRules:[{frequency:"daily",interval:1,daysOfWeek:[],weekdayOrdinals:[],daysOfMonth:[],monthsOfYear:[],weeksOfYear:[],daysOfYear:[],setPositions:[],end:{endDate:null,occurrenceCount:2}}]
}' >"$TMP_DIR/input.json"

"$CLI" reminders create --input "$TMP_DIR/input.json" --apply --format json >"$TMP_DIR/created.json"
current_id="$(jq -er '.data.reminder.id' "$TMP_DIR/created.json")"
current_due="$(jq -er '.data.reminder.due.value' "$TMP_DIR/created.json")"
jq -e '.ok == true and .data.reminder.hasRecurrenceRules == true' "$TMP_DIR/created.json" >/dev/null

"$CLI" reminders complete --id "$current_id" --apply --format json >"$TMP_DIR/completed.json"
jq -e '.ok == true and .data.operation == "completed" and .data.changed == true' "$TMP_DIR/completed.json" >/dev/null

next="$("$CLI" reminders query --status incomplete --title "$TITLE" --limit 20 --format json)"
next_id="$(printf '%s' "$next" | jq -er --arg title "$TITLE" '[.data.items[] | select(.title == $title and .completed == false)] | first | .id')"
next_due="$(printf '%s' "$next" | jq -er --arg title "$TITLE" '[.data.items[] | select(.title == $title and .completed == false)] | first | .due.value')"
[[ "$next_due" != "$current_due" ]] || { echo "Recurring completion did not advance the due date." >&2; exit 1; }

response_next="$(jq -r '.data.nextOccurrence.id // empty' "$TMP_DIR/completed.json")"
if [[ -n "$response_next" && "$response_next" != "$next_id" ]]; then
  echo "nextOccurrence does not match the next incomplete query result." >&2
  exit 1
fi
response_next_due="$(jq -r '.data.nextOccurrence.due.value // empty' "$TMP_DIR/completed.json")"
if [[ -n "$response_next_due" && "$response_next_due" != "$next_due" ]]; then
  echo "nextOccurrence due date does not match the next incomplete query result." >&2
  exit 1
fi

cleanup
trap - EXIT
remaining="$("$CLI" reminders query --status all --title "$TITLE" --limit 20 --format json)"
printf '%s' "$remaining" | jq -e --arg title "$TITLE" '[.data.items[] | select(.title == $title)] | length == 0' >/dev/null

if [[ "$next_id" == "$current_id" ]]; then
  identity_result="opaque ID was reused"
else
  identity_result="opaque ID changed"
fi
echo "Reminders recurring completion integration passed; due date advanced ($identity_result) and final matching count is zero."
