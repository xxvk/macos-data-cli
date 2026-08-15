#!/usr/bin/env bash
set -euo pipefail

APP="${MPIA_APP:-}"
ACCOUNT_ID="${NOTES_ACCOUNT_ID:-}"
APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true
[[ $# -le 1 ]] || { echo "Usage: run_notes_folder_integration.sh [--apply]" >&2; exit 1; }
[[ -n "$APP" && -d "$APP" ]] || { echo "Set MPIA_APP to a signed app bundle." >&2; exit 1; }
[[ -n "$ACCOUNT_ID" ]] || { echo "Set NOTES_ACCOUNT_ID to the already-bound opaque iCloud Notes account ID." >&2; exit 1; }
command -v jq >/dev/null || { echo "Notes folder integration requires jq." >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
NONCE="$(date +%s)-$$"
ROOT_NAME="mpia-folder-gate-root-$NONCE"
DESTINATION_NAME="mpia-folder-gate-destination-$NONCE"
CHILD_NAME="mpia-folder-gate-child-$NONCE"
RENAMED_NAME="mpia-folder-gate-renamed-$NONCE"
ROOT_ID=""
ROOT_HASH=""
DESTINATION_ID=""
CHILD_ID=""
CURRENT_STAGE="initialization"

cleanup() {
  local status=$?
  rm -rf "$TMP_DIR"
  if [[ $status -ne 0 ]]; then
    echo "Notes folder gate stopped; stage=$CURRENT_STAGE rootID=${ROOT_ID:-unknown} destinationID=${DESTINATION_ID:-unknown} childID=${CHILD_ID:-unknown}. Do not retry automatically." >&2
  fi
  exit "$status"
}
trap cleanup EXIT

sha256_text() {
  printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
}

run_app() {
  local output_path="$1"
  shift
  local error_path="$output_path.stderr"
  /usr/bin/open -n -o "$output_path" --stderr "$error_path" "$APP" --args "$@" >/dev/null 2>&1 || true
  for _ in {1..200}; do
    [[ -s "$output_path" || -s "$error_path" ]] && break
    sleep 0.1
  done
  if [[ ! -s "$output_path" && -s "$error_path" ]]; then
    cp "$error_path" "$output_path"
  fi
  [[ -s "$output_path" ]] || {
    echo "Notes folder gate failed without private folder names; stage=$CURRENT_STAGE rootID=${ROOT_ID:-unknown} destinationID=${DESTINATION_ID:-unknown} childID=${CHILD_ID:-unknown}. Do not retry automatically." >&2
    exit 1
  }
}

CURRENT_STAGE="permission"
run_app "$TMP_DIR/permission.json" notes permission --format json
jq -e '.ok == true and .data.access == "available"' "$TMP_DIR/permission.json" >/dev/null

CURRENT_STAGE="write-account-status"
run_app "$TMP_DIR/status.json" notes write-account status --format json
jq -e --arg account "$ACCOUNT_ID" '.ok == true and .data.bound == true and .data.valid == true and .data.accountID == $account' "$TMP_DIR/status.json" >/dev/null

jq -cn --arg name "$ROOT_NAME" '{name:$name,parentFolderID:null}' >"$TMP_DIR/root.json"
CURRENT_STAGE="root-create-preview"
run_app "$TMP_DIR/root-preview.json" notes folder create --input "$TMP_DIR/root.json" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true and .data.changed == true and .data.name == null' "$TMP_DIR/root-preview.json" >/dev/null

if [[ "$APPLY" != true ]]; then
  echo "Notes folder integration dry-run passed; no Notes folder was created. Re-run with --apply for the disposable runtime gate."
  exit 0
fi

CURRENT_STAGE="root-create-apply"
run_app "$TMP_DIR/root-result.json" notes folder create --input "$TMP_DIR/root.json" --apply --idempotent --format json
jq -e '.ok == true and .data.verification == "readback_confirmed" and .data.name == null' "$TMP_DIR/root-result.json" >/dev/null
ROOT_ID="$(jq -r '.data.folderID' "$TMP_DIR/root-result.json")"
ROOT_HASH="$(jq -r '.data.nameSHA256' "$TMP_DIR/root-result.json")"

CURRENT_STAGE="duplicate-create-rejection"
run_app "$TMP_DIR/duplicate.json" notes folder create --input "$TMP_DIR/root.json" --dry-run --format json
jq -e '.ok == false and .error.code == "NOTES_DUPLICATE_FOLDER_NAME"' "$TMP_DIR/duplicate.json" >/dev/null

jq -cn --arg name "$DESTINATION_NAME" '{name:$name,parentFolderID:null}' >"$TMP_DIR/destination.json"
CURRENT_STAGE="destination-create-apply"
run_app "$TMP_DIR/destination-result.json" notes folder create --input "$TMP_DIR/destination.json" --apply --idempotent --format json
jq -e '.ok == true and .data.verification == "readback_confirmed" and .data.name == null' "$TMP_DIR/destination-result.json" >/dev/null
DESTINATION_ID="$(jq -r '.data.folderID' "$TMP_DIR/destination-result.json")"

jq -cn --arg name "$CHILD_NAME" --arg parent "$ROOT_ID" '{name:$name,parentFolderID:$parent}' >"$TMP_DIR/child.json"
CURRENT_STAGE="nested-create-apply"
run_app "$TMP_DIR/child-result.json" notes folder create --input "$TMP_DIR/child.json" --apply --idempotent --format json
jq -e --arg parent "$ROOT_ID" '.ok == true and .data.verification == "readback_confirmed" and .data.parentFolderID == $parent and .data.name == null' "$TMP_DIR/child-result.json" >/dev/null
CHILD_ID="$(jq -r '.data.folderID' "$TMP_DIR/child-result.json")"

CHILD_HASH="$(sha256_text "$CHILD_NAME")"
jq -cn --arg name "$RENAMED_NAME" --arg hash "$CHILD_HASH" '{name:$name,expectedNameSHA256:$hash}' >"$TMP_DIR/rename.json"
CURRENT_STAGE="rename-preview"
run_app "$TMP_DIR/rename-preview.json" notes folder rename --id "$CHILD_ID" --input "$TMP_DIR/rename.json" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true and .data.changed == true and .data.name == null' "$TMP_DIR/rename-preview.json" >/dev/null
CURRENT_STAGE="rename-apply"
run_app "$TMP_DIR/rename-result.json" notes folder rename --id "$CHILD_ID" --input "$TMP_DIR/rename.json" --apply --format json
jq -e '.ok == true and .data.verification == "readback_confirmed" and .data.name == null' "$TMP_DIR/rename-result.json" >/dev/null
CHILD_ID="$(jq -r '.data.folderID' "$TMP_DIR/rename-result.json")"

RENAMED_HASH="$(sha256_text "$RENAMED_NAME")"
jq -cn --arg destination "$DESTINATION_ID" --arg current "$ROOT_ID" --arg hash "$RENAMED_HASH" \
  '{destinationParentFolderID:$destination,expectedParentFolderID:$current,expectedNameSHA256:$hash}' >"$TMP_DIR/move.json"
CURRENT_STAGE="move-preview"
run_app "$TMP_DIR/move-preview.json" notes folder move --id "$CHILD_ID" --input "$TMP_DIR/move.json" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true and .data.changed == true and .data.name == null' "$TMP_DIR/move-preview.json" >/dev/null
CURRENT_STAGE="move-apply"
run_app "$TMP_DIR/move-result.json" notes folder move --id "$CHILD_ID" --input "$TMP_DIR/move.json" --apply --format json
jq -e '.ok == false and .error.code == "NOTES_FOLDER_MOVE_UNSUPPORTED"' "$TMP_DIR/move-result.json" >/dev/null

jq -cn --arg destination "$CHILD_ID" --arg hash "$ROOT_HASH" \
  '{destinationParentFolderID:$destination,expectedParentFolderID:null,expectedNameSHA256:$hash}' >"$TMP_DIR/cycle.json"
CURRENT_STAGE="cycle-rejection"
run_app "$TMP_DIR/cycle-result.json" notes folder move --id "$ROOT_ID" --input "$TMP_DIR/cycle.json" --dry-run --format json
jq -e '.ok == false and .error.code == "NOTES_FOLDER_CYCLE"' "$TMP_DIR/cycle-result.json" >/dev/null

CURRENT_STAGE="final-readback"
run_app "$TMP_DIR/folders.json" notes folders --account-id "$ACCOUNT_ID" --limit 200 --format json
jq -e --arg child "$CHILD_ID" --arg root "$ROOT_ID" \
  '(.ok == true and .data.complete == true) and ([.data.items[] | select(.id == $child and .parentID == $root)] | length == 1)' \
  "$TMP_DIR/folders.json" >/dev/null
ACTUAL_HASH="$(jq -j --arg child "$CHILD_ID" '.data.items[] | select(.id == $child) | .name' "$TMP_DIR/folders.json" | shasum -a 256 | awk '{print $1}')"
[[ "$ACTUAL_HASH" == "$RENAMED_HASH" ]] || { echo "Notes folder read-back hash mismatch. Do not retry automatically." >&2; exit 1; }

jq -cn --arg parent "$ROOT_ID" --arg hash "$RENAMED_HASH" '{expectedParentFolderID:$parent,expectedNameSHA256:$hash}' >"$TMP_DIR/delete-child.json"
CURRENT_STAGE="delete-child-preview"
run_app "$TMP_DIR/delete-child-preview.json" notes folder delete --id "$CHILD_ID" --input "$TMP_DIR/delete-child.json" --dry-run --format json
jq -e '.ok == true and .data.dryRun == true and .data.changed == true' "$TMP_DIR/delete-child-preview.json" >/dev/null
CURRENT_STAGE="delete-apply-fail-closed"
run_app "$TMP_DIR/delete-child-result.json" notes folder delete --id "$CHILD_ID" --input "$TMP_DIR/delete-child.json" --apply --confirm "DELETE EMPTY NOTES FOLDER" --format json
jq -e '.ok == false and .error.code == "NOTES_FOLDER_DELETE_UNSUPPORTED"' "$TMP_DIR/delete-child-result.json" >/dev/null

echo "Notes folder create/rename integration passed; move and delete apply failed closed. Disposable UI cleanup required for three opaque folders: rootID=$ROOT_ID destinationID=$DESTINATION_ID childID=$CHILD_ID"
