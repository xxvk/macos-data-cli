#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 700 "$TMP_DIR"

[[ -x "$CLI" ]] || { echo "Calendar smoke CLI not found: $CLI" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required for privacy-safe aggregate validation." >&2; exit 1; }

START="$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')"
END="$(date -u -v+90d '+%Y-%m-%dT%H:%M:%SZ')"

"$CLI" calendar sources --format json >"$TMP_DIR/sources.json"
"$CLI" calendar calendars --format json >"$TMP_DIR/calendars.json"
"$CLI" calendar query --start "$START" --end "$END" --limit 50 --format json >"$TMP_DIR/events.json"

jq -e '.ok == true and .contractVersion == "0.1"' "$TMP_DIR/sources.json" >/dev/null
jq -e '.data as $d | [$d.sources[] | select(.identifier == $d.selectedSourceID and .isICloud == true)] | length == 1' "$TMP_DIR/sources.json" >/dev/null
jq -e '.ok == true and (.data.calendars | type == "array")' "$TMP_DIR/calendars.json" >/dev/null
jq -e '.ok == true and (.data.items | type == "array") and ([.data.items[].id | startswith("calevent_")] | all)' "$TMP_DIR/events.json" >/dev/null

source_count="$(jq '.data.sources | length' "$TMP_DIR/sources.json")"
calendar_count="$(jq '.data.calendars | length' "$TMP_DIR/calendars.json")"
event_count="$(jq '.data.items | length' "$TMP_DIR/events.json")"
truncated="$(jq '.data.truncated' "$TMP_DIR/events.json")"

echo "Calendar read smoke passed: sources=$source_count calendars=$calendar_count events_in_page=$event_count truncated=$truncated"
