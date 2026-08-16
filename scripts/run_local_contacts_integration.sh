#!/usr/bin/env bash
set -euo pipefail

# Explicitly local: this script is not a CI test and is never invoked by
# swift test. It uses the already documented iCloud Contacts fixtures.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="${MPIA_BIN:-$ROOT_DIR/.build/debug/mpia}"
if [[ ! -x "$CLI" ]]; then
  CLI="${MPIA_BIN:-$ROOT_DIR/.build/arm64-apple-macosx/debug/mpia}"
fi
if [[ ! -x "$CLI" ]]; then
  CLI="${MPIA_BIN:-$(command -v mpia || true)}"
fi
if [[ -z "$CLI" || ! -x "$CLI" ]]; then
  echo "mpia binary not found; run swift build first or set MPIA_BIN" >&2
  exit 1
fi

PERSON_ID="xvk-test-contacts-001"
ORGANIZATION_ID="xvk-test-organizations-001"
CREATE_ID="org-create-apply-001"
TEMP_ID="xvk-integration-20260716-001"
MIGRATED_ID="xvk-integration-20260716-002"
TEMP_FIXTURE="$ROOT_DIR/Tests/Fixtures/integration-contact.json"
PATCH_FIXTURE="$ROOT_DIR/Tests/Fixtures/contact-patch.json"
AVATAR_FIXTURE="$ROOT_DIR/docs/development/icon1.png"
WITH_WRITES=false

if [[ "${1:-}" == "--with-writes" ]]; then
  WITH_WRITES=true
elif [[ "${1:-}" != "" ]]; then
  echo "Usage: $0 [--with-writes]" >&2
  exit 64
fi

run() {
  echo "+ $CLI $*"
  "$CLI" "$@"
}

echo "== Contacts local integration smoke test =="
echo "CLI: $CLI"
run HEAD /contacts/container
run HEAD /contacts/count
run GET /contacts/get --params "$(jq -cn --arg id "$PERSON_ID" '{"external-id":$id}')"
run GET /contacts/get --params "$(jq -cn --arg id "$ORGANIZATION_ID" '{"external-id":$id}')"
run GET /contacts/get --params "$(jq -cn --arg id "$CREATE_ID" '{"external-id":$id}')"
run GET /contacts/query --params '{"organization":"mpia Test Organization"}'
run POST /contacts/export --params "$(jq -cn --arg output "${TMPDIR:-/tmp}/mpia-contacts-snapshot.json" '{output:$output}')"
run POST /contacts/create --body "$(jq -c . "$ROOT_DIR/Tests/Fixtures/organization-create.json")" --dry-run
run PATCH /contacts/edit --params "$(jq -cn --arg id "$PERSON_ID" '{"external-id":$id}')" --body "$(jq -c . "$PATCH_FIXTURE")" --dry-run
run PATCH /contacts/avatar/edit --params "$(jq -cn --arg id "$PERSON_ID" --arg image "$AVATAR_FIXTURE" '{"external-id":$id,image:$image}')" --dry-run
run DELETE /contacts/delete --params "$(jq -cn --arg id "$PERSON_ID" '{"external-id":$id}')" --dry-run
run POST /contacts/external-id/migrate --params "$(jq -cn --arg from "$PERSON_ID" --arg to "xvk-test-contacts-preview-001" '{from:$from,to:$to}')" --dry-run

if [[ "$WITH_WRITES" != true ]]; then
  echo "Read-only/dry-run integration checks passed."
  exit 0
fi

created=false
cleanup() {
  if [[ "$created" == true ]]; then
    echo "Cleaning up temporary contact: $TEMP_ID"
    "$CLI" DELETE /contacts/delete --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')" --apply --confirm "DELETE CONTACT" || true
  fi
}
trap cleanup EXIT

run POST /contacts/create --body "$(jq -c . "$TEMP_FIXTURE")" --apply
created=true
run GET /contacts/get --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')"
replacement_result="$("$CLI" PUT /contacts/avatar/replace --params "$(jq -cn --arg id "$TEMP_ID" --arg image "$AVATAR_FIXTURE" '{"external-id":$id,image:$image}')" --apply --confirm "RECREATE CONTACT")"
echo "$replacement_result"
if ! echo "$replacement_result" | rg -q '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|save_accepted|verification_unknown)"'; then
  echo "Avatar replacement did not return a recognized verification status" >&2
  exit 1
fi
run PATCH /contacts/edit --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')" --body "$(jq -c . "$PATCH_FIXTURE")" --apply
image_result="$("$CLI" PATCH /contacts/avatar/edit --params "$(jq -cn --arg id "$TEMP_ID" --arg image "$AVATAR_FIXTURE" '{"external-id":$id,image:$image}')" --apply)"
echo "$image_result"
if ! echo "$image_result" | rg -q '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|save_accepted|verification_unknown)"'; then
  echo "Avatar write did not return a recognized verification status" >&2
  exit 1
fi
run POST /contacts/external-id/migrate --params "$(jq -cn --arg from "$TEMP_ID" --arg to "$MIGRATED_ID" '{from:$from,to:$to}')" --apply --confirm "CHANGE EXTERNAL ID"
TEMP_ID="$MIGRATED_ID"
run GET /contacts/get --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')"
run DELETE /contacts/delete --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')" --apply --confirm "DELETE CONTACT"
created=false

if "$CLI" GET /contacts/get --params "$(jq -cn --arg id "$TEMP_ID" '{"external-id":$id}')"; then
  echo "Expected deleted contact lookup to fail" >&2
  exit 1
fi
echo "Full local CRUD integration checks passed."
