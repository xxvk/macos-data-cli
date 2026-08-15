#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
WITH_WRITES=false
CONFIRMATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-writes) WITH_WRITES=true; shift ;;
    --confirm) [[ $# -ge 2 ]] || { echo "--confirm requires a value" >&2; exit 64; }; CONFIRMATION="$2"; shift 2 ;;
    *) echo "usage: $0 [--with-writes --confirm \"CALENDAR CRUD TEST\"]" >&2; exit 64 ;;
  esac
done

bash "$ROOT_DIR/scripts/run_calendar_read_smoke.sh"
bash "$ROOT_DIR/scripts/run_calendar_dry_run_smoke.sh"

if [[ "$WITH_WRITES" != true ]]; then
  echo "Calendar integration passed without writes."
  exit 0
fi

[[ "$CONFIRMATION" == "CALENDAR CRUD TEST" ]] || {
  echo "Real Calendar writes require --with-writes --confirm \"CALENDAR CRUD TEST\"." >&2
  exit 64
}

TMP_DIR="$(mktemp -d)"
EVENT_ID=""
trap '
  if [[ -n "$EVENT_ID" ]]; then
    "$CLI" calendar delete --id "$EVENT_ID" --apply --confirm "DELETE EVENT" --format json >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
' EXIT
chmod 700 "$TMP_DIR"

START="$(date -u -v+7d '+%Y-%m-%dT%H:%M:%SZ')"
END="$(date -u -v+7d -v+1H '+%Y-%m-%dT%H:%M:%SZ')"
SUFFIX="$(date -u '+%Y%m%dT%H%M%SZ')-$$"

jq -n --arg start "$START" --arg end "$END" --arg suffix "$SUFFIX" '{
  title: ("mpia disposable Calendar integration " + $suffix),
  startDate: $start,
  endDate: $end,
  timeZone: "Asia/Tokyo",
  notes: "Disposable mpia integration fixture; safe to delete."
}' >"$TMP_DIR/create.json"

"$CLI" calendar create --input "$TMP_DIR/create.json" --apply --format json >"$TMP_DIR/created.json"
jq -e '.ok == true and .data.operation == "created" and (.data.event.id | startswith("calevent_"))' "$TMP_DIR/created.json" >/dev/null
EVENT_ID="$(jq -r '.data.event.id' "$TMP_DIR/created.json")"

"$CLI" calendar get --id "$EVENT_ID" --format json >"$TMP_DIR/read-created.json"
jq -e --arg id "$EVENT_ID" '.ok == true and .data.id == $id' "$TMP_DIR/read-created.json" >/dev/null

jq -n --arg suffix "$SUFFIX" '{title: ("mpia disposable Calendar integration updated " + $suffix)}' >"$TMP_DIR/patch.json"
"$CLI" calendar edit --id "$EVENT_ID" --input "$TMP_DIR/patch.json" --apply --format json >"$TMP_DIR/updated.json"
jq -e '.ok == true and .data.operation == "updated"' "$TMP_DIR/updated.json" >/dev/null
EVENT_ID="$(jq -r '.data.event.id' "$TMP_DIR/updated.json")"

"$CLI" calendar get --id "$EVENT_ID" --format json >"$TMP_DIR/read-updated.json"
jq -e --arg suffix "$SUFFIX" '.ok == true and .data.title == ("mpia disposable Calendar integration updated " + $suffix)' "$TMP_DIR/read-updated.json" >/dev/null

"$CLI" calendar delete --id "$EVENT_ID" --apply --confirm "DELETE EVENT" --format json >"$TMP_DIR/deleted.json"
jq -e '.ok == true and .data.operation == "deleted"' "$TMP_DIR/deleted.json" >/dev/null

set +e
"$CLI" calendar get --id "$EVENT_ID" --format json >"$TMP_DIR/absent.json" 2>&1
absent_code=$?
set -e
[[ "$absent_code" -eq 5 ]] || { echo "Deleted Calendar event remained readable." >&2; exit 1; }
jq -e '.ok == false and .error.code == "CALENDAR_EVENT_NOT_FOUND"' "$TMP_DIR/absent.json" >/dev/null
EVENT_ID=""

echo "Disposable Calendar CRUD integration passed and the test event was removed."
