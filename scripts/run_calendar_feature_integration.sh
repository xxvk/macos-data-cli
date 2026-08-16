#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
CONFIRMATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) [[ $# -ge 2 ]] || exit 64; CONFIRMATION="$2"; shift 2 ;;
    *) echo "usage: $0 --confirm \"CALENDAR FEATURE TEST\"" >&2; exit 64 ;;
  esac
done

[[ "$CONFIRMATION" == "CALENDAR FEATURE TEST" ]] || {
  echo "Real Calendar feature writes require --confirm \"CALENDAR FEATURE TEST\"." >&2
  exit 64
}
[[ -x "$CLI" ]] || { echo "CLI not found: $CLI" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
chmod 700 "$TMP_DIR"
SUFFIX="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
URL_VALUE="https://example.invalid/mpia/calendar-feature-test/$SUFFIX"
ALL_DAY_START="$(date -v+30d '+%Y-%m-%d')"
ALL_DAY_END="$(date -v+32d '+%Y-%m-%d')"
ALL_DAY_EDITED_END="$(date -v+33d '+%Y-%m-%d')"
QUERY_START="$(date -u -v+29d '+%Y-%m-%dT00:00:00Z')"
QUERY_END="$(date -u -v+35d '+%Y-%m-%dT00:00:00Z')"
TIMED_A_START="$(date -u -v+31d '+%Y-%m-%dT10:00:00Z')"
TIMED_A_END="$(date -u -v+31d '+%Y-%m-%dT11:00:00Z')"
TIMED_B_START="$(date -u -v+31d '+%Y-%m-%dT10:30:00Z')"
TIMED_B_END="$(date -u -v+31d '+%Y-%m-%dT11:30:00Z')"
TIMED_C_START="$TIMED_B_END"
TIMED_C_END="$(date -u -v+31d '+%Y-%m-%dT12:00:00Z')"
ABSOLUTE_ALARM="$(date -u -v+29d '+%Y-%m-%dT12:00:00Z')"

query_fixture() {
  "$CLI" GET /calendar/query --params "$(jq -cn --arg start "$QUERY_START" --arg end "$QUERY_END" '{start:$start,end:$end,limit:200}')" \
    | jq --arg url "$URL_VALUE" '[.data.items[] | select(.url == $url)] | sort_by(.startDate)'
}

wait_for_fixture_count() {
  local expected="$1"
  local output="$2"
  local count=0
  for _ in {1..20}; do
    query_fixture >"$output"
    count="$(jq 'length' "$output")"
    [[ "$count" -eq "$expected" ]] && return 0
    sleep 0.25
  done
  echo "Calendar fixture visibility mismatch: expected=$expected observed=$count" >&2
  return 1
}

cleanup() {
  set +e
  query_fixture >"$TMP_DIR/cleanup.json" 2>/dev/null
  jq -r '.[].id' "$TMP_DIR/cleanup.json" 2>/dev/null | while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    "$CLI" DELETE /calendar/delete --params "$(jq -cn --arg id "$id" '{id:$id}')" --apply --confirm "DELETE EVENT" >/dev/null 2>&1 || true
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

jq -n \
  --arg title "mpia disposable all-day $SUFFIX" \
  --arg start "$ALL_DAY_START" --arg end "$ALL_DAY_END" --arg url "$URL_VALUE" '{
    title: $title,
    allDay: true,
    startDate: $start,
    endDate: $end,
    timeZone: "Asia/Tokyo",
    url: $url,
    alarms: [{relativeMinutes: -15}]
  }' >"$TMP_DIR/all-day-create.json"

"$CLI" POST /calendar/create --body "$(jq -c . "$TMP_DIR/all-day-create.json")" --apply >"$TMP_DIR/all-day-created.json"
ALL_DAY_ID="$(jq -r '.data.event.id' "$TMP_DIR/all-day-created.json")"
"$CLI" GET /calendar/get --params "$(jq -cn --arg id "$ALL_DAY_ID" '{id:$id}')" >"$TMP_DIR/all-day-read.json"
jq -e --arg start "$ALL_DAY_START" --arg end "$ALL_DAY_END" '
  .ok == true and .data.allDay == true and .data.startDate == $start and .data.endDate == $end
  and .data.alarms == [{"relativeMinutes":-15}]
' "$TMP_DIR/all-day-read.json" >/dev/null
echo "feature gate: all-day date-only and relative alarm read-back"

jq -n --arg absolute "$ABSOLUTE_ALARM" --arg end "$ALL_DAY_EDITED_END" '{
  endDate: $end,
  alarms: [{absoluteDate: $absolute}]
}' >"$TMP_DIR/all-day-edit.json"
"$CLI" PATCH /calendar/edit --params "$(jq -cn --arg id "$ALL_DAY_ID" '{id:$id}')" --body "$(jq -c . "$TMP_DIR/all-day-edit.json")" --apply >"$TMP_DIR/all-day-edited.json"
ALL_DAY_ID="$(jq -r '.data.event.id' "$TMP_DIR/all-day-edited.json")"
"$CLI" GET /calendar/get --params "$(jq -cn --arg id "$ALL_DAY_ID" '{id:$id}')" >"$TMP_DIR/absolute-read.json"
jq -e --arg end "$ALL_DAY_EDITED_END" '
  .ok == true and .data.allDay == true and .data.endDate == $end
  and (.data.alarms | length) == 1 and .data.alarms[0].absoluteDate != null
' "$TMP_DIR/absolute-read.json" >/dev/null
echo "feature gate: absolute alarm replacement"

printf '%s' '{"alarms":[]}' >"$TMP_DIR/clear-alarms.json"
"$CLI" PATCH /calendar/edit --params "$(jq -cn --arg id "$ALL_DAY_ID" '{id:$id}')" --body "$(jq -c . "$TMP_DIR/clear-alarms.json")" --apply >"$TMP_DIR/alarms-cleared.json"
ALL_DAY_ID="$(jq -r '.data.event.id' "$TMP_DIR/alarms-cleared.json")"
"$CLI" GET /calendar/get --params "$(jq -cn --arg id "$ALL_DAY_ID" '{id:$id}')" >"$TMP_DIR/cleared-read.json"
jq -e '.ok == true and .data.alarms == []' "$TMP_DIR/cleared-read.json" >/dev/null
echo "feature gate: alarm clear read-back"

create_timed_fixture() {
  local label="$1" start="$2" end="$3" output="$4"
  jq -n --arg title "mpia disposable conflict $label $SUFFIX" \
    --arg start "$start" --arg end "$end" --arg url "$URL_VALUE" '{
      title: $title, startDate: $start, endDate: $end, timeZone: "UTC", url: $url
    }' >"$TMP_DIR/$label-create.json"
  "$CLI" POST /calendar/create --body "$(jq -c . "$TMP_DIR/$label-create.json")" --apply >"$output"
}

create_timed_fixture A "$TIMED_A_START" "$TIMED_A_END" "$TMP_DIR/a.json"
create_timed_fixture B "$TIMED_B_START" "$TIMED_B_END" "$TMP_DIR/b.json"
create_timed_fixture C "$TIMED_C_START" "$TIMED_C_END" "$TMP_DIR/c.json"
wait_for_fixture_count 4 "$TMP_DIR/four-fixtures.json"
A_ID="$(jq -r --arg title "mpia disposable conflict A $SUFFIX" '.[] | select(.title == $title) | .id' "$TMP_DIR/four-fixtures.json")"
B_ID="$(jq -r --arg title "mpia disposable conflict B $SUFFIX" '.[] | select(.title == $title) | .id' "$TMP_DIR/four-fixtures.json")"
C_ID="$(jq -r --arg title "mpia disposable conflict C $SUFFIX" '.[] | select(.title == $title) | .id' "$TMP_DIR/four-fixtures.json")"

jq -n --arg title "mpia disposable conflict A $SUFFIX" \
  --arg start "$TIMED_A_START" --arg end "$TIMED_B_END" --arg url "$URL_VALUE" '{
    title: $title, startDate: $start, endDate: $end, timeZone: "UTC", url: $url,
    notes: "different persisted payload"
  }' >"$TMP_DIR/idempotency-conflict.json"
set +e
"$CLI" POST /calendar/create --params '{"idempotent":true}' --body "$(jq -c . "$TMP_DIR/idempotency-conflict.json")" --apply >"$TMP_DIR/idempotency-conflict-result.json" 2>&1
IDEMPOTENCY_EXIT=$?
set -e
[[ "$IDEMPOTENCY_EXIT" -eq 5 ]] || { echo "Expected idempotency conflict exit 5, got $IDEMPOTENCY_EXIT" >&2; exit 1; }
jq -e '.ok == false and .error.code == "CALENDAR_IDEMPOTENCY_CONFLICT"' "$TMP_DIR/idempotency-conflict-result.json" >/dev/null
wait_for_fixture_count 4 "$TMP_DIR/four-fixtures.json"
echo "feature gate: non-equivalent idempotent retry rejected without duplicate"

"$CLI" GET /calendar/conflicts --params "$(jq -cn --arg start "$QUERY_START" --arg end "$QUERY_END" '{start:$start,end:$end}')" >"$TMP_DIR/conflicts.json"
jq -e --arg a "$A_ID" --arg b "$B_ID" --arg c "$C_ID" '
  [.data.conflicts[] | select((.firstEventID == $a and .secondEventID == $b) or (.firstEventID == $b and .secondEventID == $a))] | length == 1
' "$TMP_DIR/conflicts.json" >/dev/null
jq -e --arg b "$B_ID" --arg c "$C_ID" '
  [.data.conflicts[] | select((.firstEventID == $b and .secondEventID == $c) or (.firstEventID == $c and .secondEventID == $b))] | length == 0
' "$TMP_DIR/conflicts.json" >/dev/null
echo "feature gate: strict overlap detected and adjacent boundary ignored"

jq -r '.[].id' "$TMP_DIR/four-fixtures.json" | while IFS= read -r id; do
  "$CLI" DELETE /calendar/delete --params "$(jq -cn --arg id "$id" '{id:$id}')" --apply --confirm "DELETE EVENT" >/dev/null
done
wait_for_fixture_count 0 "$TMP_DIR/final.json"

trap - EXIT
rm -rf "$TMP_DIR"
echo "Disposable Calendar feature integration passed: all-day, alarm lifecycle, conflicts, and final cleanup."
