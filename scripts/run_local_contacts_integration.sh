#!/usr/bin/env bash
set -euo pipefail

# Explicitly local: this script is not a CI test and is never invoked by
# swift test. It uses the already documented iCloud Contacts fixtures.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="${MACOS_DATA_BIN:-$ROOT_DIR/.build/debug/macos-data}"
if [[ ! -x "$CLI" ]]; then
  CLI="${MACOS_DATA_BIN:-$ROOT_DIR/.build/arm64-apple-macosx/debug/macos-data}"
fi
if [[ ! -x "$CLI" ]]; then
  CLI="${MACOS_DATA_BIN:-$(command -v macos-data || true)}"
fi
if [[ -z "$CLI" || ! -x "$CLI" ]]; then
  echo "macos-data binary not found; run swift build first or set MACOS_DATA_BIN" >&2
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
run contacts container --format json
run contacts count
run contacts get --external-id "$PERSON_ID" --format json
run contacts get --external-id "$ORGANIZATION_ID" --format json
run contacts get --external-id "$CREATE_ID" --format json
run contacts query --organization "macos-data Test Organization" --format json
run contacts export --format json --output "${TMPDIR:-/tmp}/macos-data-contacts-snapshot.json"
run contacts create --input "$ROOT_DIR/Tests/Fixtures/organization-create.json" --dry-run --format json
run contacts edit --external-id "$PERSON_ID" --input "$PATCH_FIXTURE" --dry-run --format json
run contacts edit --external-id "$PERSON_ID" --image "$AVATAR_FIXTURE" --dry-run --format json
run contacts delete --external-id "$PERSON_ID" --dry-run --format json
run contacts external-id migrate --from "$PERSON_ID" --to "xvk-test-contacts-preview-001" --dry-run --format json

if [[ "$WITH_WRITES" != true ]]; then
  echo "Read-only/dry-run integration checks passed."
  exit 0
fi

created=false
cleanup() {
  if [[ "$created" == true ]]; then
    echo "Cleaning up temporary contact: $TEMP_ID"
    "$CLI" contacts delete --external-id "$TEMP_ID" --apply --confirm "DELETE CONTACT" --format json || true
  fi
}
trap cleanup EXIT

run contacts create --input "$TEMP_FIXTURE" --apply --format json
created=true
run contacts get --external-id "$TEMP_ID" --format json
replacement_result="$("$CLI" contacts avatar replace --external-id "$TEMP_ID" --image "$AVATAR_FIXTURE" --apply --confirm "RECREATE CONTACT" --format json)"
echo "$replacement_result"
if ! echo "$replacement_result" | rg -q '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|save_accepted|verification_unknown)"'; then
  echo "Avatar replacement did not return a recognized verification status" >&2
  exit 1
fi
run contacts edit --external-id "$TEMP_ID" --input "$PATCH_FIXTURE" --apply --format json
image_result="$("$CLI" contacts edit --external-id "$TEMP_ID" --image "$AVATAR_FIXTURE" --apply --format json)"
echo "$image_result"
if ! echo "$image_result" | rg -q '"status"[[:space:]]*:[[:space:]]*"(readback_confirmed|save_accepted|verification_unknown)"'; then
  echo "Avatar write did not return a recognized verification status" >&2
  exit 1
fi
run contacts external-id migrate --from "$TEMP_ID" --to "$MIGRATED_ID" --apply --confirm "CHANGE EXTERNAL ID" --format json
TEMP_ID="$MIGRATED_ID"
run contacts get --external-id "$TEMP_ID" --format json
run contacts delete --external-id "$TEMP_ID" --apply --confirm "DELETE CONTACT" --format json
created=false

if "$CLI" contacts get --external-id "$TEMP_ID" --format json; then
  echo "Expected deleted contact lookup to fail" >&2
  exit 1
fi
echo "Full local CRUD integration checks passed."
