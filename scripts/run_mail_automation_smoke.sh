#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data.app/Contents/MacOS/macos-data}"
WITH_TEXT_FALLBACK=false
GUI_SESSION=false

for argument in "$@"; do
  case "$argument" in
    --with-text-fallback) WITH_TEXT_FALLBACK=true ;;
    --gui-session) GUI_SESSION=true ;;
    *) echo "usage: $0 [--with-text-fallback] [--gui-session]" >&2; exit 64 ;;
  esac
done

if [[ ! -x "$CLI" ]]; then
  echo "mail automation smoke: executable not found: $CLI" >&2
  exit 1
fi

RUNNER=()
if [[ "$GUI_SESSION" == true ]]; then
  RUNNER=(launchctl asuser "$(id -u)")
fi

run_cli() {
  "${RUNNER[@]}" "$CLI" "$@"
}

TEMP_DIR="$(mktemp -d /private/tmp/macos-data-mail-automation.XXXXXX)"
trap '/bin/rm -rf -- "$TEMP_DIR"' EXIT

doctor_file="$TEMP_DIR/doctor.json"
query_file="$TEMP_DIR/query.json"
metadata_file="$TEMP_DIR/metadata.json"
fallback_file="$TEMP_DIR/fallback.json"
reveal_file="$TEMP_DIR/reveal.json"

run_cli mail doctor --format json > "$doctor_file"
[[ "$(/usr/bin/jq -r '.data.automation' "$doctor_file")" == available ]]
[[ "$(/usr/bin/jq -r '.data.fastPathAvailable' "$doctor_file")" == true ]]

run_cli mail query --limit 200 --format json > "$query_file"
first_id="$(/usr/bin/jq -r '.data.messages[0].id // empty' "$query_file")"
if [[ -z "$first_id" ]]; then
  echo "mail automation smoke: no message available for reveal" >&2
  exit 1
fi

run_cli mail reveal --id "$first_id" --format json > "$reveal_file"
[[ "$(/usr/bin/jq -r '.data.backend' "$reveal_file")" == mail_app ]]
[[ "$(/usr/bin/jq -r '.data.revealed' "$reveal_file")" == true ]]

fallback_status=not_requested
if [[ "$WITH_TEXT_FALLBACK" == true ]]; then
  fallback_status=no_metadata_only_candidate
  while IFS= read -r candidate_id; do
    run_cli mail get --id "$candidate_id" --format json > "$metadata_file"
    if [[ "$(/usr/bin/jq -r '.data.cacheState' "$metadata_file")" == metadata_only ]]; then
      run_cli mail get --id "$candidate_id" --content text --format json > "$fallback_file"
      backend="$(/usr/bin/jq -r '.data.backend' "$fallback_file")"
      if [[ "$backend" == mail_app ]]; then
        fallback_status=verified
      else
        fallback_status=cache_became_available
      fi
      break
    fi
  done < <(/usr/bin/jq -r '.data.messages[].id' "$query_file")
fi

echo "mail automation smoke passed: doctor=available reveal=verified text_fallback=$fallback_status"
