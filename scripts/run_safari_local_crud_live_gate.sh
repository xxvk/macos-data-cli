#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
SOURCE="$HOME/Library/Safari/Bookmarks.plist"
STATE_DIR="$HOME/Library/Application Support/mpia-cli/recovery/safari-local-live-gate"
RECEIPT="$STATE_DIR/receipt.json"
PHASE="${1:-}"
CONFIRMATION="${2:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077

fail() { printf '%s\n' "Safari local CRUD live gate failed safely: $1" >&2; exit 1; }
require_quiet() {
  ! pgrep -x Safari >/dev/null || fail "Safari is running"
  ! lsof "$SOURCE" >/dev/null 2>&1 || fail "Bookmarks.plist has an open handle"
}
snapshot() {
  "$CLI" GET /safari/bookmarks/list --params '{"limit":200}' >"$1.bookmarks"
  "$CLI" GET /safari/reading-list/list --params '{"limit":200}' >"$1.reading"
  jq -e '.ok == true and .data.complete == true' "$1.bookmarks" >/dev/null
  jq -e '.ok == true and .data.complete == true' "$1.reading" >/dev/null
  # Safari normalizes the two built-in root titles after opening. Treat those
  # system-only spellings as equivalent while keeping every user node exact.
  jq -S '.data.items | map(
    if .kind == "folder" and (has("parentID") | not) then
      if (.title == "Bookmarks" or .title == "Bookmarks Bar" or .title == "BookmarksBar") then .title = "BookmarksBar"
      elif (.title == "Bookmarks Menu" or .title == "BookmarksMenu") then .title = "BookmarksMenu"
      else . end
    else . end
  )' "$1.bookmarks" | shasum -a 256 | awk '{print $1}'
  jq -S '.data.items' "$1.reading" | shasum -a 256 | awk '{print $1}'
}
apply_json() {
  local collection="$1" action="$2" input="$3" confirmation="${4:-}"
  local method
  case "$action" in
    create) method=POST ;;
    edit|move|rename) method=PATCH ;;
    delete) method=DELETE ;;
    *) fail "unsupported local mutation action: $action" ;;
  esac
  "$CLI" "$method" "/safari/$collection/$action" --body "$(jq -c . "$input")" --dry-run >"$TMP_DIR/preview.json"
  local source_hash
  source_hash="$(jq -er '.data.sourceSHA256Before' "$TMP_DIR/preview.json")"
  jq --arg hash "$source_hash" '. + {expectedSourceSHA256:$hash}' "$input" >"$TMP_DIR/apply-input.json"
  if [[ -n "$confirmation" ]]; then
    "$CLI" "$method" "/safari/$collection/$action" --body "$(jq -c . "$TMP_DIR/apply-input.json")" --apply --confirm "$confirmation" >"$TMP_DIR/apply.json"
  else
    "$CLI" "$method" "/safari/$collection/$action" --body "$(jq -c . "$TMP_DIR/apply-input.json")" --apply >"$TMP_DIR/apply.json"
  fi
  jq -e '.ok == true and .data.verification == "readback_confirmed" and .data.syncStatus == "local_only"' "$TMP_DIR/apply.json" >/dev/null
}

[[ -x "$CLI" ]] || fail "CLI is unavailable"
[[ -f "$SOURCE" ]] || fail "Bookmarks.plist is unavailable"

case "$PHASE" in
  create)
    [[ "$CONFIRMATION" == "CREATE SAFARI 0.8.3 LOCAL CRUD FIXTURE" ]] || fail "wrong create confirmation"
    [[ ! -e "$RECEIPT" ]] || fail "a live-gate receipt already exists"
    require_quiet
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    snapshot "$TMP_DIR/before" >"$TMP_DIR/before.hashes"
    baseline_bookmarks="$(sed -n '1p' "$TMP_DIR/before.hashes")"
    baseline_reading="$(sed -n '2p' "$TMP_DIR/before.hashes")"
    parent_a="$(jq -er '.data.items[] | select(.kind == "folder") | .id' "$TMP_DIR/before.bookmarks" | sed -n '1p')"
    parent_b="$(jq -er --arg first "$parent_a" '.data.items[] | select(.kind == "folder" and .id != $first) | .id' "$TMP_DIR/before.bookmarks" | sed -n '1p')"
    [[ -n "$parent_a" && -n "$parent_b" ]] || fail "two writable folder candidates were not found"
    marker="mpia-083-local-$(uuidgen | tr '[:upper:]' '[:lower:]')"

    jq -n --arg parent "$parent_a" --arg title "$marker-folder" '{parentID:$parent,index:0,title:$title}' >"$TMP_DIR/folder-create.json"
    apply_json folders create "$TMP_DIR/folder-create.json"
    folder_id="$(jq -er '.data.targetID' "$TMP_DIR/apply.json")"

    jq -n --arg parent "$folder_id" --arg title "$marker-bookmark" --arg url "https://example.com/$marker" '{parentID:$parent,index:0,title:$title,url:$url}' >"$TMP_DIR/bookmark-create.json"
    apply_json bookmarks create "$TMP_DIR/bookmark-create.json"
    bookmark_id="$(jq -er '.data.targetID' "$TMP_DIR/apply.json")"

    jq -n --arg marker "$marker" --arg folder "$folder_id" --arg bookmark "$bookmark_id" \
      --arg parentA "$parent_a" --arg parentB "$parent_b" --arg bb "$baseline_bookmarks" --arg br "$baseline_reading" \
      '{schemaVersion:1,stage:"awaiting_ui_readback",marker:$marker,folderID:$folder,bookmarkID:$bookmark,parentA:$parentA,parentB:$parentB,baselineBookmarksSHA256:$bb,baselineReadingSHA256:$br}' >"$RECEIPT"
    chmod 600 "$RECEIPT"
    printf '{"stage":"awaiting_ui_readback","fixtureCount":2,"marker":"%s","syncStatus":"local_only"}\n' "$marker"
    ;;
  finish)
    [[ "$CONFIRMATION" == "CLEAN SAFARI 0.8.3 LOCAL CRUD FIXTURE" ]] || fail "wrong cleanup confirmation"
    [[ -f "$RECEIPT" && "$(stat -f '%Lp' "$RECEIPT")" == "600" ]] || fail "private receipt is unavailable"
    [[ "$(jq -er '.stage' "$RECEIPT")" == "awaiting_ui_readback" ]] || fail "receipt stage is invalid"
    require_quiet
    marker="$(jq -er '.marker' "$RECEIPT")"
    folder_id="$(jq -er '.folderID' "$RECEIPT")"
    bookmark_id="$(jq -er '.bookmarkID' "$RECEIPT")"
    parent_a="$(jq -er '.parentA' "$RECEIPT")"
    parent_b="$(jq -er '.parentB' "$RECEIPT")"

    jq -n --arg id "$bookmark_id" --arg title "$marker-bookmark-edited" --arg url "https://example.com/$marker/edited" '{id:$id,title:$title,url:$url}' >"$TMP_DIR/bookmark-edit.json"
    apply_json bookmarks edit "$TMP_DIR/bookmark-edit.json"
    jq -n --arg id "$folder_id" --arg title "$marker-folder-renamed" '{id:$id,title:$title}' >"$TMP_DIR/folder-rename.json"
    apply_json folders rename "$TMP_DIR/folder-rename.json"
    jq -n --arg id "$bookmark_id" --arg parent "$parent_a" '{id:$id,parentID:$parent,index:0}' >"$TMP_DIR/bookmark-move.json"
    apply_json bookmarks move "$TMP_DIR/bookmark-move.json"
    jq -n --arg id "$folder_id" --arg parent "$parent_b" '{id:$id,parentID:$parent,index:0}' >"$TMP_DIR/folder-move.json"
    apply_json folders move "$TMP_DIR/folder-move.json"
    jq -n --arg id "$bookmark_id" '{id:$id}' >"$TMP_DIR/bookmark-delete.json"
    apply_json bookmarks delete "$TMP_DIR/bookmark-delete.json" "DELETE SAFARI BOOKMARK"
    jq -n --arg id "$folder_id" '{id:$id}' >"$TMP_DIR/folder-delete.json"
    apply_json folders delete "$TMP_DIR/folder-delete.json" "DELETE SAFARI FOLDER"

    snapshot "$TMP_DIR/after" >"$TMP_DIR/after.hashes"
    [[ "$(sed -n '1p' "$TMP_DIR/after.hashes")" == "$(jq -er '.baselineBookmarksSHA256' "$RECEIPT")" ]] || fail "bookmark projection did not return to baseline"
    [[ "$(sed -n '2p' "$TMP_DIR/after.hashes")" == "$(jq -er '.baselineReadingSHA256' "$RECEIPT")" ]] || fail "Reading List projection changed"
    [[ "$(jq --arg marker "$marker" '[.data.items[] | select(.title | contains($marker))] | length' "$TMP_DIR/after.bookmarks")" == "0" ]] || fail "fixture residue remains"
    jq '.stage = "completed_local_zero_residue"' "$RECEIPT" >"$TMP_DIR/completed.json"
    mv "$TMP_DIR/completed.json" "$RECEIPT"
    chmod 600 "$RECEIPT"
    printf '%s\n' '{"stage":"completed_local_zero_residue","fixtureCount":0,"projectionRestored":true,"syncStatus":"local_only"}'
    ;;
  *) fail "usage: create|finish with the exact confirmation phrase" ;;
esac
