#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="${2:-}"

if [[ "${1:-}" != "--session" || ! "$SESSION" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo 'Use: --session <uuid>' >&2
  exit 2
fi

cd "$ROOT_DIR"
MACOS_DATA_SAFARI_READBACK_SESSION="$SESSION" \
  bash scripts/run_swift_tests.sh --filter SafariPlistMutationFeasibilityTests.liveFixtureReadbackAudit
