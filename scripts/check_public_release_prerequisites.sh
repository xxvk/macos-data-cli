#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE="${MACOS_DATA_NOTARY_PROFILE:-macos-data-notary}"
CASK_FILE="${MACOS_DATA_CASK_FILE:-}"
failures=0

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

info() {
  echo "INFO $1"
}

cd "$ROOT_DIR"
expected_version="$(tr -d '[:space:]' < VERSION)"
release_cli="$ROOT_DIR/.build/release/macos-data"

if [[ -n "$expected_version" ]]; then
  pass "source version=$expected_version"
else
  fail "VERSION is empty"
fi

if [[ -x "$release_cli" ]] && [[ "$("$release_cli" --version)" == "$expected_version" ]]; then
  pass "release binary version=$expected_version"
else
  fail "release binary is missing or its version differs from VERSION"
fi

if [[ -z "$(git status --porcelain)" ]]; then
  pass "Git worktree is clean"
else
  fail "Git worktree is not clean"
fi

release_tag="v$expected_version"
if git rev-parse -q --verify "refs/tags/$release_tag" >/dev/null; then
  info "release tag already exists: $release_tag"
else
  info "release tag is not created yet: $release_tag"
fi

identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if /usr/bin/grep -q 'Developer ID Application:' <<<"$identities"; then
  pass "Developer ID Application identity is available"
else
  fail "Developer ID Application identity is unavailable"
fi

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  pass "notarytool keychain profile is usable: $NOTARY_PROFILE"
else
  fail "notarytool keychain profile is unavailable: $NOTARY_PROFILE"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  pass "GitHub CLI authentication is valid"
else
  fail "GitHub CLI authentication is unavailable or invalid"
fi

if [[ -n "$CASK_FILE" ]]; then
  if [[ -f "$CASK_FILE" ]]; then
    pass "Homebrew Cask file is available"
  else
    fail "MACOS_DATA_CASK_FILE does not name a file"
  fi
else
  info "MACOS_DATA_CASK_FILE is not set; Cask update will be handled separately"
fi

if [[ $failures -gt 0 ]]; then
  echo "Public release preflight failed: failures=$failures"
  exit 1
fi

echo "Public release preflight passed: version=$expected_version"
