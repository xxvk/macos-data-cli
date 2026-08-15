#!/usr/bin/env bash
set -euo pipefail

CONFIRMATION="${2:-}"

if [[ "${1:-}" != "--confirm" || "$CONFIRMATION" != "CREATE SAFARI 0.8.1 FIXTURE" ]]; then
  echo 'Refusing live mutation. Use: --confirm "CREATE SAFARI 0.8.1 FIXTURE"' >&2
  exit 2
fi

echo 'Refusing duplicate live mutation: the one-time 0.8.1 local fixture already exists and must not be retried.' >&2
echo 'Direct plist writes are local-only; use a separately gated Safari-owned import for iCloud sync.' >&2
exit 3
