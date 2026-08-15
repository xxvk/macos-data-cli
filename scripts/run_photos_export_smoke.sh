#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MPIA_APP:-}"
[[ -n "$APP" && -d "$APP" ]] || { echo "Set MPIA_APP to a signed app bundle." >&2; exit 1; }
command -v jq >/dev/null || { echo "Photos export smoke requires jq." >&2; exit 1; }

ALLOW_NETWORK=false
if [[ "${1:-}" == "--allow-network" ]]; then
  ALLOW_NETWORK=true
  shift
fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--allow-network]" >&2; exit 64; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
START="${PHOTOS_SMOKE_START:-$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')}"
END="${PHOTOS_SMOKE_END:-$(date -u -v+1d '+%Y-%m-%dT%H:%M:%SZ')}"

run_app() {
  local output_path="$1"
  shift
  local error_path="$output_path.stderr"
  /usr/bin/open -n -W -o "$output_path" --stderr "$error_path" "$APP" --args "$@" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    [[ -s "$output_path" || -s "$error_path" ]] && break
    sleep 0.1
  done
}

run_app "$TMP_DIR/query.json" photos query --start "$START" --end "$END" --limit 5 --format json
jq -e '.ok == true and (.data.items | type == "array")' "$TMP_DIR/query.json" >/dev/null

candidate_count="$(jq -r '.data.items | length' "$TMP_DIR/query.json")"
content_not_local=0
exported=false
if [[ "$candidate_count" -gt 0 ]]; then
for index in $(seq 0 $((candidate_count - 1))); do
  asset_id="$(jq -r --argjson index "$index" '.data.items[$index].id' "$TMP_DIR/query.json")"
  output_file="$TMP_DIR/exported-asset"
  export_arguments=(photos export --id "$asset_id" --output "$output_file")
  if [[ "$ALLOW_NETWORK" == true ]]; then
    export_arguments+=(--allow-network)
  fi
  export_arguments+=(--format json)
  run_app "$TMP_DIR/export-$index.json" "${export_arguments[@]}"
  if [[ -s "$TMP_DIR/export-$index.json" ]]; then
    jq -e --arg id "$asset_id" --argjson network "$ALLOW_NETWORK" '.ok == true and .data.id == $id and .data.variant == "original" and .data.networkAllowed == $network and .data.bytes > 0' "$TMP_DIR/export-$index.json" >/dev/null
    reported_bytes="$(jq -r '.data.bytes' "$TMP_DIR/export-$index.json")"
    actual_bytes="$(stat -f '%z' "$output_file")"
    permissions="$(stat -f '%Lp' "$output_file")"
    [[ "$reported_bytes" == "$actual_bytes" && "$permissions" == "600" ]] || {
      echo "Photos export smoke failed file verification." >&2
      exit 1
    }
    exported=true
    break
  fi
  if [[ -s "$TMP_DIR/export-$index.json.stderr" ]] && jq -e '.error.code == "PHOTOS_CONTENT_NOT_LOCAL"' "$TMP_DIR/export-$index.json.stderr" >/dev/null 2>&1; then
    content_not_local=$((content_not_local + 1))
    if [[ "$ALLOW_NETWORK" == true ]]; then
      echo "Photos network export was explicitly enabled but content remained unavailable." >&2
      exit 1
    fi
    continue
  fi
  echo "Photos export smoke failed with an unexpected private error response." >&2
  exit 1
done
fi

echo "Photos export smoke passed: candidates=$candidate_count exported=$exported contentNotLocal=$content_not_local networkAllowed=$ALLOW_NETWORK outputRemovedOnExit=true"
