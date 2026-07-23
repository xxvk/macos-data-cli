#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$CLI" ]]; then
  echo "CLI not found or not executable: $CLI" >&2
  echo "Run: swift build" >&2
  exit 1
fi

"$CLI" mail doctor --format json >"$TMP_DIR/doctor.json"

for pattern in \
  '"ok"[[:space:]]*:[[:space:]]*true' \
  '"contractVersion"[[:space:]]*:[[:space:]]*"0.1"' \
  '"mailStoreVersion"' \
  '"schema"' \
  '"fullDiskAccess"' \
  '"automation"' \
  '"fastPathAvailable"'; do
  if ! rg -q "$pattern" "$TMP_DIR/doctor.json"; then
    echo "mail doctor response missing: $pattern" >&2
    exit 1
  fi
done

if [[ "${1:-}" == "--require-fast-path" ]] &&
  ! rg -q '"fastPathAvailable"[[:space:]]*:[[:space:]]*true' "$TMP_DIR/doctor.json"; then
  echo "Mail fast path is not available on this host." >&2
  exit 1
fi

echo "Mail doctor smoke test passed."
