#!/usr/bin/env bash
set -euo pipefail

APP="${MACOS_DATA_APP:-}"
ACCOUNT_ID="${NOTES_ACCOUNT_ID:-}"
SOURCE_FOLDER_ID="${NOTES_SOURCE_FOLDER_ID:-}"
DESTINATION_FOLDER_ID="${NOTES_DESTINATION_FOLDER_ID:-}"
WITH_SOFT_DELETE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-soft-delete) WITH_SOFT_DELETE=true; shift ;;
    *) echo "usage: $0 [--with-soft-delete]" >&2; exit 64 ;;
  esac
done
[[ -n "$APP" && -d "$APP" ]] || { echo "Set MACOS_DATA_APP to a signed app bundle." >&2; exit 1; }
[[ -n "$ACCOUNT_ID" && -n "$SOURCE_FOLDER_ID" && -n "$DESTINATION_FOLDER_ID" ]] || {
  echo "Set NOTES_ACCOUNT_ID, NOTES_SOURCE_FOLDER_ID, and NOTES_DESTINATION_FOLDER_ID." >&2
  exit 1
}
[[ "$SOURCE_FOLDER_ID" != "$DESTINATION_FOLDER_ID" ]] || { echo "Source and destination folders must differ." >&2; exit 1; }
command -v jq >/dev/null || { echo "Notes write integration requires jq." >&2; exit 1; }
command -v shasum >/dev/null || { echo "Notes write integration requires shasum." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
TITLE="${NOTES_TEST_TITLE:-macos-data-notes-write-gate-$(date +%s)-$$}"
RENAMED_TITLE="${TITLE}-renamed"
EDITED_BODY="Disposable macos-data 0.6.2 body-edit integration fixture."
NOTE_ID=""
CURRENT_STAGE="initialization"
trap 'rm -rf "$TMP_DIR"' EXIT

run_app() {
  local output_path="$1"
  shift
  local error_path="$output_path.stderr"
  /usr/bin/open -n -o "$output_path" --stderr "$error_path" "$APP" --args "$@" >/dev/null 2>&1 || true
  for _ in {1..400}; do
    [[ -s "$output_path" || -s "$error_path" ]] && break
    sleep 0.1
  done
  [[ -s "$output_path" ]] || {
    echo "Notes write gate failed; stage=$CURRENT_STAGE noteID=${NOTE_ID:-unknown}. Do not retry automatically." >&2
    exit 1
  }
}

CURRENT_STAGE="permission"
run_app "$TMP_DIR/permission.json" notes permission --format json
jq -e '.ok == true and .data.access == "available"' "$TMP_DIR/permission.json" >/dev/null

CURRENT_STAGE="bind-preview"
run_app "$TMP_DIR/bind-preview.json" notes write-account bind --account-id "$ACCOUNT_ID" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true' "$TMP_DIR/bind-preview.json" >/dev/null
CURRENT_STAGE="bind-apply"
run_app "$TMP_DIR/bind.json" notes write-account bind --account-id "$ACCOUNT_ID" --apply --confirm "BIND ICLOUD NOTES" --format json
jq -e '.ok == true and .data.dryRun == false' "$TMP_DIR/bind.json" >/dev/null

jq -cn --arg folder "$SOURCE_FOLDER_ID" --arg title "$TITLE" \
  '{folderID:$folder,title:$title,bodyFormat:"plaintext",body:"Disposable macos-data 0.6.2 integration fixture."}' >"$TMP_DIR/create-input.json"
CURRENT_STAGE="create-preview"
run_app "$TMP_DIR/create-preview.json" notes create --input "$TMP_DIR/create-input.json" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true and .data.title == null and .data.body == null' "$TMP_DIR/create-preview.json" >/dev/null
CURRENT_STAGE="create-apply"
run_app "$TMP_DIR/create.json" notes create --input "$TMP_DIR/create-input.json" --apply --idempotent --format json
jq -e '.ok == true and .data.verification == "readback_confirmed"' "$TMP_DIR/create.json" >/dev/null || {
  jq -c '{ok,verification:.data.verification,noteID:.data.noteID,nextAction:.data.nextAction,error:.error}' "$TMP_DIR/create.json" >&2
  exit 1
}
NOTE_ID="$(jq -r '.data.noteID' "$TMP_DIR/create.json")"

CURRENT_STAGE="get-created-body"
run_app "$TMP_DIR/get-created.json" notes get --id "$NOTE_ID" --body plaintext --format json
CREATED_MODIFIED="$(jq -r '.data.note.modificationDate' "$TMP_DIR/get-created.json")"
CREATED_BODY_SHA256="$(jq -j '.data.body' "$TMP_DIR/get-created.json" | shasum -a 256 | awk '{print $1}')"
jq -cn --arg body "$EDITED_BODY" --arg modified "$CREATED_MODIFIED" --arg hash "$CREATED_BODY_SHA256" \
  '{bodyFormat:"plaintext",body:$body,expectedModificationDate:$modified,expectedBodySHA256:$hash}' >"$TMP_DIR/edit-body-input.json"
CURRENT_STAGE="edit-body-preview"
run_app "$TMP_DIR/edit-body-preview.json" notes edit-body --id "$NOTE_ID" --input "$TMP_DIR/edit-body-input.json" --dry-run --format json
jq -e --arg hash "$CREATED_BODY_SHA256" \
  '.ok == true and .data.dryRun == true and .data.changed == true and .data.previousBodySHA256 == $hash' \
  "$TMP_DIR/edit-body-preview.json" >/dev/null
CURRENT_STAGE="edit-body-apply"
run_app "$TMP_DIR/edit-body.json" notes edit-body --id "$NOTE_ID" --input "$TMP_DIR/edit-body-input.json" --apply --format json
jq -e '.ok == true and .data.verification == "readback_confirmed" and .data.changed == true' "$TMP_DIR/edit-body.json" >/dev/null || {
  jq -c '{ok,verification:.data.verification,noteID:.data.noteID,nextAction:.data.nextAction,error:.error}' "$TMP_DIR/edit-body.json" >&2
  exit 1
}
EXPECTED_EDITED_SHA256="$(jq -r '.data.bodySHA256' "$TMP_DIR/edit-body.json")"
CURRENT_STAGE="get-edited-body"
run_app "$TMP_DIR/get-edited.json" notes get --id "$NOTE_ID" --body plaintext --format json
ACTUAL_EDITED_SHA256="$(jq -j '.data.body' "$TMP_DIR/get-edited.json" | shasum -a 256 | awk '{print $1}')"
[[ "$ACTUAL_EDITED_SHA256" == "$EXPECTED_EDITED_SHA256" ]] || {
  echo "Notes body read-back hash mismatch; noteID=$NOTE_ID. Do not retry automatically." >&2
  exit 1
}

CREATED_MODIFIED="$(jq -r '.data.note.modificationDate' "$TMP_DIR/get-edited.json")"
jq -cn --arg title "$RENAMED_TITLE" --arg modified "$CREATED_MODIFIED" \
  '{title:$title,expectedModificationDate:$modified}' >"$TMP_DIR/rename-input.json"
CURRENT_STAGE="rename-apply"
run_app "$TMP_DIR/rename.json" notes rename --id "$NOTE_ID" --input "$TMP_DIR/rename-input.json" --apply --format json
jq -e '.ok == true and .data.verification == "readback_confirmed"' "$TMP_DIR/rename.json" >/dev/null || {
  jq -c '{ok,verification:.data.verification,noteID:.data.noteID,nextAction:.data.nextAction,error:.error}' "$TMP_DIR/rename.json" >&2
  exit 1
}

CURRENT_STAGE="get-renamed"
run_app "$TMP_DIR/get-renamed.json" notes get --id "$NOTE_ID" --format json
RENAMED_MODIFIED="$(jq -r '.data.note.modificationDate' "$TMP_DIR/get-renamed.json")"
jq -cn --arg folder "$DESTINATION_FOLDER_ID" --arg modified "$RENAMED_MODIFIED" \
  '{destinationFolderID:$folder,expectedModificationDate:$modified}' >"$TMP_DIR/move-input.json"
CURRENT_STAGE="move-apply"
run_app "$TMP_DIR/move.json" notes move --id "$NOTE_ID" --input "$TMP_DIR/move-input.json" --apply --format json
jq -e --arg folder "$DESTINATION_FOLDER_ID" '.ok == true and .data.verification == "readback_confirmed" and .data.folderID == $folder' "$TMP_DIR/move.json" >/dev/null || {
  jq -c '{ok,verification:.data.verification,noteID:.data.noteID,folderID:.data.folderID,nextAction:.data.nextAction,error:.error}' "$TMP_DIR/move.json" >&2
  exit 1
}
NOTE_ID="$(jq -r '.data.noteID' "$TMP_DIR/move.json")"

CURRENT_STAGE="final-query"
run_app "$TMP_DIR/query.json" notes query --folder-id "$DESTINATION_FOLDER_ID" --title "$RENAMED_TITLE" --limit 10 --format json
jq -e --arg id "$NOTE_ID" '[.data.items[] | select(.id == $id)] | length == 1' "$TMP_DIR/query.json" >/dev/null

if [[ "$WITH_SOFT_DELETE" == true ]]; then
  CURRENT_STAGE="get-before-delete"
  run_app "$TMP_DIR/get-before-delete.json" notes get --id "$NOTE_ID" --format json
  DELETE_MODIFIED="$(jq -r '.data.note.modificationDate' "$TMP_DIR/get-before-delete.json")"
  jq -cn --arg modified "$DELETE_MODIFIED" \
    '{expectedModificationDate:$modified}' >"$TMP_DIR/delete-input.json"
  CURRENT_STAGE="delete-preview"
  run_app "$TMP_DIR/delete-preview.json" notes delete --id "$NOTE_ID" --input "$TMP_DIR/delete-input.json" --dry-run --format json
  jq -e '.ok == true and .data.dryRun == true and .data.changed == true and .data.title == null and .data.body == null' "$TMP_DIR/delete-preview.json" >/dev/null
  CURRENT_STAGE="delete-apply"
  run_app "$TMP_DIR/delete.json" notes delete --id "$NOTE_ID" --input "$TMP_DIR/delete-input.json" --apply --confirm "DELETE NOTE" --format json
  jq -e --arg source "$DESTINATION_FOLDER_ID" \
    '.ok == true and .data.verification == "readback_confirmed" and .data.changed == true and .data.folderID != $source' \
    "$TMP_DIR/delete.json" >/dev/null || {
      jq -c '{ok,verification:.data.verification,noteID:.data.noteID,folderID:.data.folderID,nextAction:.data.nextAction,error:.error}' "$TMP_DIR/delete.json" >&2
      exit 1
    }
  NOTE_ID="$(jq -r '.data.noteID' "$TMP_DIR/delete.json")"
  CURRENT_STAGE="verify-source-absence"
  run_app "$TMP_DIR/source-absence.json" notes query --folder-id "$DESTINATION_FOLDER_ID" --title "$RENAMED_TITLE" --limit 10 --format json
  jq -e '.ok == true and .data.complete == true and (.data.items | length) == 0' "$TMP_DIR/source-absence.json" >/dev/null
  CURRENT_STAGE="verify-recoverable-presence"
  run_app "$TMP_DIR/recoverable-presence.json" notes query --title "$RENAMED_TITLE" --limit 10 --format json
  jq -e --arg source "$DESTINATION_FOLDER_ID" \
    '.ok == true and .data.complete == true and ([.data.items[] | select(.folderID != $source)] | length) == 1' \
    "$TMP_DIR/recoverable-presence.json" >/dev/null
  echo "Notes soft-delete integration passed. Permanent UI cleanup requires separate action-time confirmation: noteID=$NOTE_ID"
else
  echo "Notes write integration passed. Disposable cleanup required: noteID=$NOTE_ID destinationFolderID=$DESTINATION_FOLDER_ID"
fi
