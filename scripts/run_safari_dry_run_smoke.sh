#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MPIA_CLI:-$ROOT_DIR/.build/debug/mpia}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v jq >/dev/null || { echo "Safari dry-run smoke requires jq." >&2; exit 1; }
[[ -x "$CLI" ]] || { echo "mpia CLI is missing: $CLI" >&2; exit 1; }

"$CLI" POST /safari/reading-list/add \
  --body '{"url":"https://mpia.invalid/fixture-080","title":"mpia Safari dry-run"}' \
  --dry-run >"$TMP_DIR/result.json"
jq -e '.ok == true and .data.dryRun == true and .data.verification == "not_applied"' "$TMP_DIR/result.json" >/dev/null
if rg -q 'mpia\.invalid|Safari dry-run' "$TMP_DIR/result.json"; then
  echo "Safari dry-run output leaked URL or title." >&2
  exit 1
fi
echo "Safari Reading List dry-run smoke passed: mutationBridgeCalled=false privateOutputRemovedOnExit=true"
