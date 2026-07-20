# Changelog

## 0.1.7 — 2026-07-20

### Added

- Added a manual local Contacts integration smoke test with a read-only/dry-run
  mode and an explicit disposable-contact CRUD mode.
- Added `--stdin` JSON input for Contacts create and regular edit commands;
  file input remains supported.
- Added `--kind person|organization` as a Contacts query condition.
- Added opt-in idempotent create retries and `--ignore-not-found` delete retries.
- Centralized unique-match resolution so ambiguous external IDs always refuse
  automatic reads or writes.
- Added JSON contract version `0.1` to machine-readable success and error
  envelopes, and standardized `contacts count --format json`.
- Centralized and documented stable CLI exit codes and error codes.
- Redacted common contact-sensitive diagnostic values and removed underlying
  exception text from persisted logs.
- Added phonetic given/family name fields to the JSON model and Contacts mapper;
  verified apply/read-back on the fixed Japanese test contact.
- Added a local process-level CLI contract and negative-path test runner;
  unknown and missing arguments now also return the JSON error contract.
- Verified the complete local Contacts CRUD path with a temporary iCloud
  contact, including avatar update, external ID migration, deletion, and cleanup.
- Added explicit avatar write verification results, separating save acceptance
  from successful image-data read-back.
- Added a separately confirmed avatar replacement flow for records that cannot
  be safely edited in place, plus local contract coverage for its dry-run and
  confirmation guard.
- Verified the macOS 26 deployment target on macOS 27.0 with Xcode 26.6 and
  SDK 26.5; Debug and Release tests and CLI contract tests passed.

### Fixed

- Fixed `contacts export --format json --output <file>`, which previously
  failed to match the CLI argument parser after format flags were normalized.
- Apply responses for create, edit, avatar, delete, and external ID migration
  now include the final contact state in the JSON contract.
- Contact JSON now includes `imageAvailable`, read through
  `CNContactImageDataAvailableKey` without fetching avatar bytes.
- Added `contacts containers` and explicit `--container iCloud` or iCloud
  container identifier selection. Unknown or non-iCloud containers fail
  without fallback.

## 0.1.6 — 2026-07-16

### Fixed

- Synchronize the CLI-reported version with the published release.

## 0.1.4 — 2026-07-16

### Fixed

- Resolve the contact identifier without image keys, then fetch image-related keys separately before avatar writes. This fixes avatar updates for contacts without a previous image.

## 0.1.3 — 2026-07-16

### Fixed

- Request all Contacts image-related keys before writing an avatar, including for contacts that had no previous avatar.

## 0.1.2 — 2026-07-16

Patch release aligning the CLI version with the published binary and Homebrew Cask.

## 0.1.0 — 2026-07-16

First Contacts adapter release.

### Added

- Contacts permission checking and iCloud container verification
- Contact count, list, get, and multi-condition query
- Person and organization contact types
- Create, partial edit, avatar update, delete, and external ID migration
- Reserved `macos-data-cli` URL label and `x-macos-data://external-id/<id>` format
- Avatar normalization: 10 MB input, 1024 px maximum dimension, 200 KB output
- JSON snapshot export
- Structured JSON success and error responses
- TDD unit tests and documented local end-to-end fixtures

### Current limitations

- macOS 26.0+ only
- Writes require an available iCloud Contacts container
- `metadata` is preserved in JSON but is not written into Apple Contacts
- vCard import/export is not implemented
- Batch operations and sync workflows are not implemented
