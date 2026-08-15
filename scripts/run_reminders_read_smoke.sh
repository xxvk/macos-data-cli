#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"

[[ -x "$CLI" ]] || { echo "Reminders smoke requires an executable CLI: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Reminders smoke requires jq." >&2; exit 1; }

"$CLI" reminders --help | grep -q "Reminders 0.4 read commands"

resources="$("$CLI" resources --format json)"
printf '%s' "$resources" | jq -e '
  .ok == true and
  any(.data.resources[];
    .kind == "remindersSource" and
    .capabilities.selected == true and
    .capabilities.readable == true and
    .capabilities.writable == true
  )
' >/dev/null

set +e
invalid_output="$("$CLI" reminders query --status invalid --format json 2>&1)"
invalid_status=$?
set -e
[[ $invalid_status -eq 6 ]]
printf '%s' "$invalid_output" | jq -e '.ok == false and .error.code == "REMINDERS_INVALID_INPUT"' >/dev/null

sources="$("$CLI" reminders sources --format json)"
printf '%s' "$sources" | jq -e '.ok == true and (.data.sources | length) >= 1 and (.data.selectedSourceID | length) > 0' >/dev/null

lists="$("$CLI" reminders lists --format json)"
printf '%s' "$lists" | jq -e '.ok == true and (.data.lists | type) == "array" and (.data.selectedSourceID | length) > 0' >/dev/null

query="$("$CLI" reminders query --status incomplete --limit 2 --format json)"
printf '%s' "$query" | jq -e '
  .ok == true and
  (.data.items | type) == "array" and
    (.data.items | length) <= 2 and
    (all(.data.items[]; (.alarms | type) == "array" and (.recurrenceRules | type) == "array")) and
  (.data.complete | type) == "boolean" and
  (.data.truncated | type) == "boolean"
' >/dev/null

item_count="$(printf '%s' "$query" | jq -r '.data.items | length')"
reminder_id="$(printf '%s' "$query" | jq -r '.data.items[0].id // empty')"
if [[ -n "$reminder_id" ]]; then
  get_result="$("$CLI" reminders get --id "$reminder_id" --format json)"
  printf '%s' "$get_result" | jq -e '
    .ok == true and
    (.data.id | startswith("reminder_")) and
    (.data.title | type) == "string" and
    (.data.completed | type) == "boolean"
  ' >/dev/null
fi

cursor="$(printf '%s' "$query" | jq -r '.data.nextCursor // empty')"
if [[ -n "$cursor" ]]; then
  set +e
  stale_output="$("$CLI" reminders query --status completed --limit 2 --cursor "$cursor" --format json 2>&1)"
  stale_status=$?
  set -e
  [[ $stale_status -eq 6 ]]
  printf '%s' "$stale_output" | jq -e '.ok == false' >/dev/null
fi

echo "Reminders read smoke passed: sources=$(printf '%s' "$sources" | jq -r '.data.sources | length') lists=$(printf '%s' "$lists" | jq -r '.data.lists | length') queried=$item_count get=$([[ -n "$reminder_id" ]] && echo true || echo skipped)"
