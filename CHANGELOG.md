# Changelog

## 0.2.0 — 2026-07-23

### Added

- Added read-only `mail doctor --format json` with dynamic numeric `V*`
  discovery, read-only SQLite/WAL checks, schema fingerprinting, required V10
  structure recognition, Full Disk Access inference, and non-interactive
  Mail.app Automation status.
- Verified the V10 SQLite fast path on macOS 26.4 with Xcode 26.6 / SDK 26.5.
- Added Mail doctor fixtures covering highest-version selection, fail-closed
  unknown schemas, fast-path gating, and privacy-safe JSON output.
- Added read-only `mail accounts`, `mail mailboxes`, and bounded `mail query`
  commands backed by a query-only SQLite connection.
- Added opaque account, mailbox, message, and cursor IDs; bound metadata filters;
  default/maximum result limits of 50/200; a 250 ms SQLite deadline; and backend,
  cache, truncation, fallback, completeness, limitation, and elapsed-time fields.
- Added explicit `mail get` metadata/text/raw projections with variable-depth V10
  EMLX path resolution, `.partial.emlx` reporting, exact byte-count extraction,
  bounded MIME text decoding, sanitized HTML-to-text fallback, and no-overwrite
  raw file output.
- Added EMLX/MIME fixtures for Unicode byte lengths, malformed/truncated input,
  path traversal and symlink escape, partial/full precedence, transfer encodings,
  attachment exclusion, and remote-resource-free HTML handling.
- Preserved the V10 `messages_deleted_date_received_index` query plan by ordering
  directly on `date_received`; this avoids a full temporary sort under the
  250 ms metadata-query deadline.
- Added serialized Mail.app Apple Events text fallback for uncached/empty partial
  content, with a 3-second timeout, 30-second timeout circuit breaker, explicit
  backend/fallback reporting, and no automatic Mail launch for ordinary reads.
- Added `mail reveal --id <opaque-id>` as the isolated visible Mail.app action.
  Message references use the V10 mailbox account UUID/path plus validated numeric
  ROWID; Automation denial, timeout, circuit-open, and lookup failures have stable
  machine codes.
- Added a signed-app Automation smoke test and verified Automation plus real
  `mail reveal` on macOS 26.4. The bounded latest-200 sample contained no
  metadata-only message, so live text fallback was skipped rather than forced;
  deterministic fixtures cover both fallback success and failure behavior.
- Added privacy-safe `mail attachments verify`, which compares the SQLite
  attachment-row count with bounded MIME-part inspection without returning names,
  paths, or payloads. Synthetic complete/mismatch/missing fixtures pass.
- The macOS 26.4 live V10 cross-check observed 1,146 attachment rows across 509
  non-deleted messages while Mail was syncing; all 509 resolved to partial EMLX,
  so none was labeled verified. This confirms future attachment export must fail
  closed unless complete content is independently available.
- Added `run_mail_release_gate.sh` for the reproducible Xcode test, Release,
  signed Debug app, and read-only Mail smoke matrix. The non-UI gate passes on
  macOS 26.4. Its attended Automation mode also demonstrated the fail-closed
  `MAIL_APP_TIMEOUT` path while Mail was actively syncing; it did not auto-retry.
- Added a checked-in Mail Automation entitlement to the ad-hoc Debug app. The
  release gate now validates both plists, verifies the app signature, and reads
  `com.apple.security.automation.apple-events=true` back from the signed bundle.
- Added a bounded Mail.app metadata fallback for unavailable FDA or unsupported
  storage schemas. It requires a running authorized Mail.app, has a five-second
  timeout, caps enumeration at 32 accounts / 200 top-level mailboxes / 25
  messages, returns backend-specific opaque IDs, no cursor, and always marks
  queries incomplete. The privacy-safe macOS 26.4 smoke observed 3 account
  scopes and 35 top-level mailboxes and verified one targeted metadata get.
- Centralized the 0.2.0 CLI and bundle version through `VERSION` and
  `CLIVersion`, with release-gate drift checks across the binary and plists.
- Added a privacy-safe installed-release smoke. The locally installed 0.2.0
  binary passed version/help checks and used the V10 SQLite fast path for a
  bounded query on macOS 26.4.
- Added a public-release prerequisite audit for version drift, worktree state,
  Developer ID, notarization profile, GitHub authentication, and optional Cask
  checkout availability. It prints status only and performs no release action.

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
