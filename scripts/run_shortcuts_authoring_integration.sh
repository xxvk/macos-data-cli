#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia.app/Contents/MacOS/mpia}"
SOURCE="$ROOT_DIR/Tests/Fixtures/Shortcuts/echo.cherri"
UPDATED_SOURCE="$ROOT_DIR/Tests/Fixtures/Shortcuts/echo-updated.cherri"
FIXTURE_NAME="Macos Data 071 Fixture"
CONFIRMATION=""
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --confirm) [[ $# -ge 2 ]] || exit 64; CONFIRMATION="$2"; shift 2 ;;
    *) echo "usage: $0 --apply --confirm \"SHORTCUTS AUTHORING CRUD TEST\"" >&2; exit 64 ;;
  esac
done

if [[ "$APPLY" != true || "$CONFIRMATION" != "SHORTCUTS AUTHORING CRUD TEST" ]]; then
  echo "This gate visibly imports, runs, creates a retain-old candidate, and then requires UI deletion of both disposable Shortcuts." >&2
  echo "Use --apply --confirm \"SHORTCUTS AUTHORING CRUD TEST\" only after explicit current-task authorization." >&2
  exit 64
fi

command -v jq >/dev/null || { echo "Shortcuts authoring integration requires jq." >&2; exit 1; }
[[ -x "$CLI" ]] || { echo "Signed Debug CLI not found: $CLI" >&2; exit 1; }
[[ -f "$SOURCE" && -f "$UPDATED_SOURCE" ]] || { echo "Shortcuts authoring fixtures are missing." >&2; exit 1; }

TMP_DIR="$(mktemp -d /tmp/mpia-shortcuts-authoring-gate.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 700 "$TMP_DIR"
printf '%s' 'mpia-071-sentinel' >"$TMP_DIR/input.txt"
chmod 600 "$TMP_DIR/input.txt"

"$CLI" POST /shortcuts/author/validate --params "$(jq -cn --arg source "$SOURCE" '{source:$source}')" >"$TMP_DIR/validate-created.json"
"$CLI" POST /shortcuts/author/validate --params "$(jq -cn --arg source "$UPDATED_SOURCE" '{source:$source}')" >"$TMP_DIR/validate-updated.json"
SOURCE_SHA="$(jq -er '.data.sourceSHA256' "$TMP_DIR/validate-created.json")"
UPDATED_SOURCE_SHA="$(jq -er '.data.sourceSHA256' "$TMP_DIR/validate-updated.json")"
jq -e '.ok == true and .data.actionCount == 1' "$TMP_DIR/validate-created.json" >/dev/null
jq -e '.ok == true and .data.actionCount == 2' "$TMP_DIR/validate-updated.json" >/dev/null

"$CLI" POST /shortcuts/create --params "$(jq -cn --arg source "$SOURCE" '{source:$source,idempotent:true}')" --dry-run >"$TMP_DIR/create-preview.json"
jq -e --arg hash "$SOURCE_SHA" '
  .ok == true and .data.operation == "create_preview" and .data.dryRun == true
  and .data.changed == false and .data.verification == "not_applied"
  and .data.sourceSHA256 == $hash and .data.shortcutID == null
  and .data.registrySaved == false
' "$TMP_DIR/create-preview.json" >/dev/null

"$CLI" GET /shortcuts/list --params '{"limit":200}' >"$TMP_DIR/before.json"
jq -e --arg name "$FIXTURE_NAME" '[.data.items[] | select(.name == $name or (.name | startswith($name + " (mpia ")))] | length == 0' "$TMP_DIR/before.json" >/dev/null || {
  echo "Refusing to run: a Shortcut with the disposable fixture name already exists." >&2
  exit 1
}

echo "Waiting for the visible Shortcuts.app Add Shortcut confirmation..."
"$CLI" POST /shortcuts/create --params "$(jq -cn --arg source "$SOURCE" '{source:$source,idempotent:true}')" --apply \
  --confirm "CREATE MANAGED SHORTCUT" >"$TMP_DIR/created.json"
jq -e --arg hash "$SOURCE_SHA" '
  .ok == true and .data.operation == "created" and .data.verification == "readback_confirmed"
  and .data.sourceSHA256 == $hash and .data.actionCount == 1
  and (.data.observedActionCount | type == "number")
  and .data.registrySaved == true and (.data.shortcutID | startswith("shortcut_"))
' "$TMP_DIR/created.json" >/dev/null
SHORTCUT_ID="$(jq -er '.data.shortcutID' "$TMP_DIR/created.json")"

"$CLI" GET /shortcuts/get --params "$(jq -cn --arg id "$SHORTCUT_ID" '{id:$id}')" >"$TMP_DIR/get-created.json"
jq -e --arg id "$SHORTCUT_ID" --arg name "$FIXTURE_NAME" '
  .ok == true and .data.id == $id and .data.name == $name
' "$TMP_DIR/get-created.json" >/dev/null

"$CLI" POST /shortcuts/run --params "$(jq -cn --arg id "$SHORTCUT_ID" --arg input "$TMP_DIR/input.txt" '{id:$id,"input-path":[$input]}')" \
  --apply --confirm "RUN SHORTCUT" >"$TMP_DIR/run-created.json"
jq -e '.ok == true and .data.verification == "completed" and .data.output == "mpia-071-sentinel"' "$TMP_DIR/run-created.json" >/dev/null

"$CLI" PUT /shortcuts/update --params "$(jq -cn --arg id "$SHORTCUT_ID" --arg source "$UPDATED_SOURCE" --arg sha "$SOURCE_SHA" '{id:$id,source:$source,"expected-source-sha256":$sha,strategy:"retain-old"}')" \
  --dry-run >"$TMP_DIR/update-preview.json"
jq -e --arg hash "$UPDATED_SOURCE_SHA" '
  .ok == true and .data.operation == "update_preview" and .data.dryRun == true
  and .data.verification == "not_applied" and .data.sourceSHA256 == $hash
  and .data.actionCount == 2 and .data.registrySaved == true
' "$TMP_DIR/update-preview.json" >/dev/null

echo "Waiting for the visible Shortcuts.app Add Shortcut confirmation for the retain-old candidate..."
"$CLI" PUT /shortcuts/update --params "$(jq -cn --arg id "$SHORTCUT_ID" --arg source "$UPDATED_SOURCE" --arg sha "$SOURCE_SHA" '{id:$id,source:$source,"expected-source-sha256":$sha,strategy:"retain-old"}')" \
  --apply --confirm "UPDATE MANAGED SHORTCUT" >"$TMP_DIR/updated.json"
jq -e --arg old "$SHORTCUT_ID" --arg hash "$UPDATED_SOURCE_SHA" '
  .ok == true and .data.operation == "updated" and .data.verification == "readback_confirmed"
  and .data.previousShortcutID == $old and .data.sourceSHA256 == $hash
  and .data.actionCount == 2 and (.data.observedActionCount | type == "number")
  and .data.oldRetained == true
  and .data.registrySaved == true and (.data.shortcutID | startswith("shortcut_"))
' "$TMP_DIR/updated.json" >/dev/null
UPDATED_SHORTCUT_ID="$(jq -er '.data.shortcutID' "$TMP_DIR/updated.json")"
UPDATED_FIXTURE_NAME="$FIXTURE_NAME (mpia ${UPDATED_SOURCE_SHA:0:8})"

"$CLI" GET /shortcuts/get --params "$(jq -cn --arg id "$UPDATED_SHORTCUT_ID" '{id:$id}')" >"$TMP_DIR/get-updated.json"
jq -e --arg id "$UPDATED_SHORTCUT_ID" --arg name "$UPDATED_FIXTURE_NAME" '
  .ok == true and .data.id == $id and .data.name == $name
' "$TMP_DIR/get-updated.json" >/dev/null

"$CLI" POST /shortcuts/run --params "$(jq -cn --arg id "$UPDATED_SHORTCUT_ID" --arg input "$TMP_DIR/input.txt" '{id:$id,"input-path":[$input]}')" \
  --apply --confirm "RUN SHORTCUT" >"$TMP_DIR/run-updated.json"
jq -e '.ok == true and .data.verification == "completed" and .data.output == "mpia-071-sentinel"' "$TMP_DIR/run-updated.json" >/dev/null

echo "Create, run, retain-old update, and read-back passed. Delete both disposable fixture Shortcuts in Shortcuts.app, then press Return here."
read -r _

"$CLI" GET /shortcuts/list --params '{"limit":200}' >"$TMP_DIR/after-ui-delete.json"
jq -e --arg name "$FIXTURE_NAME" '[.data.items[] | select(.name == $name or (.name | startswith($name + " (mpia ")))] | length == 0' "$TMP_DIR/after-ui-delete.json" >/dev/null || {
  echo "Cleanup is not confirmed: at least one disposable Shortcut is still present." >&2
  exit 1
}

"$CLI" DELETE /shortcuts/managed/forget --params "$(jq -cn --arg id "$UPDATED_SHORTCUT_ID" '{id:$id}')" --dry-run >"$TMP_DIR/forget-preview.json"
jq -e --arg id "$UPDATED_SHORTCUT_ID" '.ok == true and .data.shortcutID == $id and .data.dryRun == true and .data.changed == false' "$TMP_DIR/forget-preview.json" >/dev/null
"$CLI" DELETE /shortcuts/managed/forget --params "$(jq -cn --arg id "$UPDATED_SHORTCUT_ID" '{id:$id}')" --apply \
  --confirm "FORGET MANAGED SHORTCUT" >"$TMP_DIR/forgotten.json"
jq -e --arg id "$UPDATED_SHORTCUT_ID" '.ok == true and .data.shortcutID == $id and .data.dryRun == false and .data.changed == true' "$TMP_DIR/forgotten.json" >/dev/null
"$CLI" GET /shortcuts/managed/list >"$TMP_DIR/managed-final.json"
jq -e --arg old "$SHORTCUT_ID" --arg current "$UPDATED_SHORTCUT_ID" '
  [.data[] | select(.shortcutID == $old or .shortcutID == $current)] | length == 0
' "$TMP_DIR/managed-final.json" >/dev/null

echo "Shortcuts 0.7.1 managed authoring integration passed (fixtureResidue=0 registryResidue=0)."
