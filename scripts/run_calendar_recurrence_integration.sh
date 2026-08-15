#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
CONFIRMATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) [[ $# -ge 2 ]] || exit 64; CONFIRMATION="$2"; shift 2 ;;
    *) echo "usage: $0 --confirm \"CALENDAR RECURRENCE TEST\"" >&2; exit 64 ;;
  esac
done

[[ "$CONFIRMATION" == "CALENDAR RECURRENCE TEST" ]] || {
  echo "Real recurring Calendar writes require --confirm \"CALENDAR RECURRENCE TEST\"." >&2
  exit 64
}

TMP_DIR="$(mktemp -d)"
chmod 700 "$TMP_DIR"
START="$(date -u -v+21d '+%Y-%m-%dT%H:%M:%SZ')"
END="$(date -u -v+21d -v+1H '+%Y-%m-%dT%H:%M:%SZ')"
QUERY_START="$(date -u -v+20d '+%Y-%m-%dT%H:%M:%SZ')"
QUERY_END="$(date -u -v+40d '+%Y-%m-%dT%H:%M:%SZ')"
SUFFIX="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
URL_VALUE="https://example.invalid/mpia/recurrence-test/$SUFFIX"

query_fixture() {
  "$CLI" calendar query --start "$QUERY_START" --end "$QUERY_END" --limit 200 --format json \
    | jq --arg url "$URL_VALUE" '[.data.items[] | select(.url == $url)] | sort_by(.startDate)'
}

cleanup() {
  set +e
  query_fixture >"$TMP_DIR/cleanup.json" 2>/dev/null
  jq -r '.[].id' "$TMP_DIR/cleanup.json" 2>/dev/null | while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    "$CLI" calendar delete --id "$id" --apply --confirm "DELETE EVENT" --span future --format json >/dev/null 2>&1 || \
      "$CLI" calendar delete --id "$id" --apply --confirm "DELETE EVENT" --span this --format json >/dev/null 2>&1 || true
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

jq -n --arg start "$START" --arg end "$END" --arg url "$URL_VALUE" --arg suffix "$SUFFIX" '{
  title: ("mpia disposable recurrence " + $suffix),
  startDate: $start,
  endDate: $end,
  timeZone: "Asia/Tokyo",
  url: $url,
  alarms: [{relativeMinutes: -10}],
  recurrenceRules: [{frequency: "daily", interval: 1, end: {occurrenceCount: 6}}]
}' >"$TMP_DIR/create.json"

"$CLI" calendar create --input "$TMP_DIR/create.json" --apply --idempotent --format json >"$TMP_DIR/created.json"
jq -e '.ok == true and .data.operation == "created"' "$TMP_DIR/created.json" >/dev/null
echo "recurrence gate: created"
"$CLI" calendar create --input "$TMP_DIR/create.json" --apply --idempotent --format json >"$TMP_DIR/retried.json"
jq -e '.ok == true and .data.operation == "existing"' "$TMP_DIR/retried.json" >/dev/null
echo "recurrence gate: idempotent retry"

query_fixture >"$TMP_DIR/initial.json"
jq -e 'length == 6 and all(.[]; .alarms[0].relativeMinutes == -10)' "$TMP_DIR/initial.json" >/dev/null
echo "recurrence gate: six occurrences and alarms"
SECOND_ID="$(jq -r '.[1].id' "$TMP_DIR/initial.json")"
FOURTH_START="$(jq -r '.[3].startDate' "$TMP_DIR/initial.json")"

printf '%s' '{"title":"mpia detached recurrence occurrence"}' >"$TMP_DIR/this-patch.json"
"$CLI" calendar edit --id "$SECOND_ID" --input "$TMP_DIR/this-patch.json" --apply --span this --format json >"$TMP_DIR/this-updated.json"
echo "recurrence gate: edited this occurrence"

query_fixture >"$TMP_DIR/after-this.json"
jq -e 'length == 6 and .[1].title == "mpia detached recurrence occurrence" and .[0].title != .[1].title and .[2].title != .[1].title' "$TMP_DIR/after-this.json" >/dev/null
FOURTH_ID="$(jq -r '.[3].id' "$TMP_DIR/after-this.json")"

printf '%s' '{"title":"mpia future recurrence occurrences"}' >"$TMP_DIR/future-patch.json"
"$CLI" calendar edit --id "$FOURTH_ID" --input "$TMP_DIR/future-patch.json" --apply --span future --format json >"$TMP_DIR/future-updated.json"
echo "recurrence gate: edited future occurrences"
query_fixture >"$TMP_DIR/after-future.json"
jq -e --arg fourth "$FOURTH_START" 'length == 6 and all(.[] | select(.startDate >= $fourth); .title == "mpia future recurrence occurrences")' "$TMP_DIR/after-future.json" >/dev/null

SECOND_ID="$(jq -r '.[1].id' "$TMP_DIR/after-future.json")"
"$CLI" calendar delete --id "$SECOND_ID" --apply --confirm "DELETE EVENT" --span this --format json >"$TMP_DIR/deleted-this.json"
echo "recurrence gate: deleted this occurrence"
query_fixture >"$TMP_DIR/after-delete-this.json"
jq -e 'length == 5' "$TMP_DIR/after-delete-this.json" >/dev/null

FOURTH_ID="$(jq -r --arg fourth "$FOURTH_START" '.[] | select(.startDate == $fourth) | .id' "$TMP_DIR/after-delete-this.json")"
"$CLI" calendar delete --id "$FOURTH_ID" --apply --confirm "DELETE EVENT" --span future --format json >"$TMP_DIR/deleted-future.json"
echo "recurrence gate: deleted future occurrences"
query_fixture >"$TMP_DIR/after-delete-future.json"
jq -e --arg fourth "$FOURTH_START" 'all(.[]; .startDate < $fourth)' "$TMP_DIR/after-delete-future.json" >/dev/null

# Remaining early occurrences are disposable fixtures and are removed before success.
jq -r '.[].id' "$TMP_DIR/after-delete-future.json" | while IFS= read -r id; do
  "$CLI" calendar delete --id "$id" --apply --confirm "DELETE EVENT" --span future --format json >/dev/null 2>&1 || \
    "$CLI" calendar delete --id "$id" --apply --confirm "DELETE EVENT" --span this --format json >/dev/null 2>&1 || true
done
query_fixture >"$TMP_DIR/final.json"
jq -e 'length == 0' "$TMP_DIR/final.json" >/dev/null

trap - EXIT
rm -rf "$TMP_DIR"
echo "Disposable recurring Calendar integration passed: idempotent retry, alarms, this/future edit, this/future delete, and final cleanup."
