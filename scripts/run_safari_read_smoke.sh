#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v jq >/dev/null || { echo "Safari read smoke requires jq." >&2; exit 1; }
[[ -x "$CLI" ]] || { echo "mpia CLI is missing: $CLI" >&2; exit 1; }

"$CLI" safari permission --format json >"$TMP_DIR/permission.json"
jq -e '.ok == true and .data.bookmarksReadable == true' "$TMP_DIR/permission.json" >/dev/null

"$CLI" safari bookmarks list --limit 1 --format json >"$TMP_DIR/bookmarks.json"
"$CLI" safari reading-list list --limit 1 --format json >"$TMP_DIR/reading-list.json"

bookmark_id="$(jq -r '.data.items[0].id // empty' "$TMP_DIR/bookmarks.json")"
reading_id="$(jq -r '.data.items[0].id // empty' "$TMP_DIR/reading-list.json")"
if [[ -n "$bookmark_id" ]]; then
  "$CLI" safari bookmarks get --id "$bookmark_id" --format json >"$TMP_DIR/bookmark-get.json"
  jq -e '.ok == true and (.data.id | startswith("safari"))' "$TMP_DIR/bookmark-get.json" >/dev/null
fi
if [[ -n "$reading_id" ]]; then
  "$CLI" safari reading-list get --id "$reading_id" --format json >"$TMP_DIR/reading-get.json"
  jq -e '.ok == true and (.data.id | startswith("safarireading_"))' "$TMP_DIR/reading-get.json" >/dev/null
fi

bookmark_count="$(jq '.data.items | length' "$TMP_DIR/bookmarks.json")"
reading_count="$(jq '.data.items | length' "$TMP_DIR/reading-list.json")"
echo "Safari read smoke passed: bookmarkSample=$bookmark_count readingListSample=$reading_count privateOutputRemovedOnExit=true"
