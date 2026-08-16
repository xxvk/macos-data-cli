#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 700 "$TMP_DIR"

[[ -x "$CLI" ]] || { echo "Calendar smoke CLI not found: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required for privacy-safe smoke validation." >&2; exit 1; }

START="$(date -u -v+2d '+%Y-%m-%dT%H:%M:%SZ')"
END="$(date -u -v+2d -v+1H '+%Y-%m-%dT%H:%M:%SZ')"
QUERY_START="$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')"
QUERY_END="$(date -u -v+90d '+%Y-%m-%dT%H:%M:%SZ')"

jq -n --arg start "$START" --arg end "$END" '{
  title: "mpia Calendar dry-run fixture",
  startDate: $start,
  endDate: $end,
  timeZone: "Asia/Tokyo",
  alarms: [{relativeMinutes: -10}],
  recurrenceRules: [{frequency: "weekly", interval: 1, end: {occurrenceCount: 2}}]
}' >"$TMP_DIR/create.json"

"$CLI" POST /calendar/create --body "$(jq -c . "$TMP_DIR/create.json")" --dry-run >"$TMP_DIR/create-preview.json"
jq -e '.ok == true and .data.operation == "create_preview" and .data.dryRun == true and .data.event.timeZone == "Asia/Tokyo" and .data.event.alarms[0].relativeMinutes == -10 and .data.event.recurrenceRules[0].frequency == "weekly"' "$TMP_DIR/create-preview.json" >/dev/null

printf '%s' '{"title":"mpia all-day dry-run fixture","allDay":true,"startDate":"2026-11-01","endDate":"2026-11-02","timeZone":"America/Los_Angeles","alarms":[]}' >"$TMP_DIR/all-day.json"
"$CLI" POST /calendar/create --params '{"idempotent":true}' --body "$(jq -c . "$TMP_DIR/all-day.json")" --dry-run >"$TMP_DIR/all-day-preview.json"
jq -e '.ok == true and .data.event.allDay == true and .data.event.startDate == "2026-11-01" and .data.event.endDate == "2026-11-02"' "$TMP_DIR/all-day-preview.json" >/dev/null

params="$(jq -cn --arg start "$QUERY_START" --arg end "$QUERY_END" '{start:$start,end:$end}')"
"$CLI" GET /calendar/conflicts --params "$params" >"$TMP_DIR/conflicts.json"
jq -e '.ok == true and (.data.checkedEventCount | type == "number") and (.data.conflicts | type == "array")' "$TMP_DIR/conflicts.json" >/dev/null

params="$(jq -cn --arg start "$QUERY_START" --arg end "$QUERY_END" '{start:$start,end:$end,limit:1}')"
"$CLI" GET /calendar/query --params "$params" >"$TMP_DIR/query.json"
jq -e '.ok == true and (.data.items | type == "array")' "$TMP_DIR/query.json" >/dev/null

# Do not use an arbitrary user event as an edit/delete dry-run fixture. EventKit
# can detach a recurring occurrence while building a preview and change its opaque
# ID even though no save occurs. Disposable real-write gates cover those paths.
echo "Calendar dry-run smoke passed: create=passed query=passed conflicts=passed edit=separate_disposable_gate delete=separate_disposable_gate"
