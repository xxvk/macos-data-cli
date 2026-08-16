#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"

[[ -x "$CLI" ]] || { echo "Reminders smoke requires an executable CLI: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Reminders smoke requires jq." >&2; exit 1; }

"$CLI" GET /agent/manifest | jq -e '[.data.routes[] | select(.path | startswith("/reminders/"))] | length == 10' >/dev/null

resources="$("$CLI" OPTIONS /resources)"
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
invalid_output="$("$CLI" GET /reminders/query --params '{"status":"invalid"}' 2>&1)"
invalid_status=$?
set -e
[[ $invalid_status -eq 6 ]]
printf '%s' "$invalid_output" | jq -e '.ok == false and .error.code == "REMINDERS_INVALID_INPUT"' >/dev/null

sources="$("$CLI" OPTIONS /reminders/sources)"
printf '%s' "$sources" | jq -e '.ok == true and (.data.sources | length) >= 1 and (.data.selectedSourceID | length) > 0' >/dev/null

lists="$("$CLI" GET /reminders/lists)"
printf '%s' "$lists" | jq -e '.ok == true and (.data.lists | type) == "array" and (.data.selectedSourceID | length) > 0' >/dev/null

query="$("$CLI" GET /reminders/query --params '{"status":"incomplete","limit":2}')"
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
  get_result="$("$CLI" GET /reminders/get --params "$(jq -cn --arg id "$reminder_id" '{id:$id}')")"
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
  stale_output="$("$CLI" GET /reminders/query --params "$(jq -cn --arg cursor "$cursor" '{status:"completed",limit:2,cursor:$cursor}')" 2>&1)"
  stale_status=$?
  set -e
  [[ $stale_status -eq 6 ]]
  printf '%s' "$stale_output" | jq -e '.ok == false' >/dev/null
fi

echo "Reminders read smoke passed: sources=$(printf '%s' "$sources" | jq -r '.data.sources | length') lists=$(printf '%s' "$lists" | jq -r '.data.lists | length') queried=$item_count get=$([[ -n "$reminder_id" ]] && echo true || echo skipped)"
