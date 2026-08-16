#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"

[[ -x "$CLI" ]] || { echo "Reminders dry-run smoke requires an executable CLI: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "Reminders dry-run smoke requires jq." >&2; exit 1; }

payload='{"title":"mpia dry-run verification","priority":"high","due":{"value":"2026-08-17","timeZone":null,"hasTime":false,"floating":true},"alarms":[{"relativeMinutes":-10}],"recurrenceRules":[]}'
preview="$("$CLI" POST /reminders/create --body "$payload" --dry-run)"
printf '%s' "$preview" | jq -e '
  .ok == true and
  .data.operation == "create_preview" and
  .data.dryRun == true and
  .data.reminder.title == "mpia dry-run verification" and
  .data.reminder.priority == "high" and
  .data.reminder.due.value == "2026-08-17" and
  (.data.reminder | has("id") | not)
' >/dev/null

absence="$("$CLI" GET /reminders/query --params '{"status":"incomplete","title":"mpia dry-run verification","limit":10}')"
printf '%s' "$absence" | jq -e '
  [.data.items[] | select(.title == "mpia dry-run verification")] | length == 0
' >/dev/null

set +e
unknown_output="$("$CLI" POST /reminders/create --body '{"title":"Task","titel":"typo"}' --dry-run 2>&1)"
unknown_status=$?
set -e
[[ $unknown_status -eq 6 ]]
printf '%s' "$unknown_output" | jq -e '
  .ok == false and .error.code == "REMINDERS_INVALID_INPUT"
' >/dev/null

echo "Reminders create dry-run smoke passed; no reminder was created."
