#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-/opt/homebrew/bin/macos-data}"

if [[ ! -x "$CLI" ]]; then
  echo "installed macos-data binary is missing or not executable: $CLI" >&2
  exit 1
fi

expected_version="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
installed_version="$($CLI --version)"
if [[ "$installed_version" != "$expected_version" ]]; then
  echo "installed version mismatch: expected=$expected_version observed=$installed_version" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d /private/tmp/macos-data-installed-smoke.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_json() {
  local output="$1"
  shift
  set +e
  "$CLI" "$@" >"$output" 2>"$TEMP_DIR/stderr.json"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    local code
    code="$(/usr/bin/jq -r '.error.code // "invalid_error_response"' "$TEMP_DIR/stderr.json" 2>/dev/null || echo invalid_error_response)"
    echo "installed binary smoke failed: code=$code processExit=$status" >&2
    return "$status"
  fi
}

"$CLI" --help >"$TEMP_DIR/help.txt"
if ! head -n 1 "$TEMP_DIR/help.txt" | rg -q '^macos-data '; then
  echo "installed binary help header is invalid" >&2
  exit 1
fi

run_json "$TEMP_DIR/doctor.json" mail doctor --format json
if ! /usr/bin/jq -e '.ok == true and .data.fastPathAvailable == true' "$TEMP_DIR/doctor.json" >/dev/null; then
  echo "installed binary Mail V10 fast path is unavailable" >&2
  exit 1
fi

run_json "$TEMP_DIR/query.json" mail query --limit 1 --format json
if ! /usr/bin/jq -e '.ok == true and .data.backend == "sqlite"' "$TEMP_DIR/query.json" >/dev/null; then
  echo "installed binary Mail query did not use the SQLite backend" >&2
  exit 1
fi

message_count="$(/usr/bin/jq -r '.data.messages | length' "$TEMP_DIR/query.json")"
echo "Installed release smoke passed: version=$installed_version backend=sqlite fastPath=true messages=$message_count"
