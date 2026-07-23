#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${MACOS_DATA_CLI:-$ROOT_DIR/.build/debug/macos-data}"
TEMP_DIR="$(mktemp -d /private/tmp/macos-data-mail-attachments.XXXXXX)"
trap '/bin/rm -rf -- "$TEMP_DIR"' EXIT

if [[ ! -x "$CLI" ]]; then
  echo "mail attachment smoke: executable not found: $CLI" >&2
  exit 1
fi

query_file="$TEMP_DIR/query.json"
result_file="$TEMP_DIR/result.json"
"$CLI" mail query --has-attachment --limit 25 --format json > "$query_file"

inspected=0
matched=0
partial=0
unavailable=0
mismatched=0
while IFS= read -r message_id; do
  "$CLI" mail attachments verify --id "$message_id" --format json > "$result_file"
  inspected=$((inspected + 1))
  cache_state="$(/usr/bin/jq -r '.data.cacheState' "$result_file")"
  mime_count="$(/usr/bin/jq -r '.data.mimeCount // "none"' "$result_file")"
  is_matched="$(/usr/bin/jq -r '.data.matched' "$result_file")"
  [[ "$cache_state" == partial ]] && partial=$((partial + 1))
  [[ "$mime_count" == none ]] && unavailable=$((unavailable + 1))
  if [[ "$is_matched" == true ]]; then
    matched=$((matched + 1))
  else
    mismatched=$((mismatched + 1))
  fi
  if rg -qi 'subject|sender|filename|/Users/' "$result_file"; then
    echo "mail attachment smoke: verification output exposed disallowed fields" >&2
    exit 1
  fi
done < <(/usr/bin/jq -r '.data.messages[].id' "$query_file")

if [[ "$inspected" -eq 0 ]]; then
  echo "mail attachment smoke: no attachment-bearing message in bounded sample" >&2
  exit 1
fi

echo "Mail attachment smoke passed: inspected=$inspected matched=$matched partial=$partial unavailable=$unavailable nonmatched=$mismatched"
