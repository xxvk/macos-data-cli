#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v jq >/dev/null || { echo "Safari dry-run smoke requires jq." >&2; exit 1; }
[[ -x "$CLI" ]] || { echo "macos-data CLI is missing: $CLI" >&2; exit 1; }

printf '%s' '{"url":"https://macos-data.invalid/fixture-080","title":"macos-data Safari dry-run"}' \
  | "$CLI" safari reading-list add --stdin --dry-run --format json >"$TMP_DIR/result.json"
jq -e '.ok == true and .data.dryRun == true and .data.verification == "not_applied"' "$TMP_DIR/result.json" >/dev/null
if rg -q 'macos-data\.invalid|Safari dry-run' "$TMP_DIR/result.json"; then
  echo "Safari dry-run output leaked URL or title." >&2
  exit 1
fi
echo "Safari Reading List dry-run smoke passed: mutationBridgeCalled=false privateOutputRemovedOnExit=true"
