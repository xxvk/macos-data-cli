#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$HOME/Library/Safari/Bookmarks.plist"

[[ -f "$SOURCE" && ! -L "$SOURCE" ]] || {
  echo "Safari Bookmarks.plist is missing or unsafe." >&2
  exit 1
}

cd "$ROOT_DIR"
MACOS_DATA_SAFARI_PLIST_COPY_AUDIT=1 \
  bash scripts/run_swift_tests.sh --filter SafariPlistMutationFeasibilityTests.liveCopyAudit
