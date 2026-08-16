# Changelog

Summary of each major version. Detailed per-patch notes live in the git history.

## 0.9 — 2026-08-16

- Renamed the project from `macos-data-cli` to `mpia-cli`: canonical command `mpia`, bundle identifier `com.xvk.mpia.cli`, and Contacts external-ID scheme `mpia://ext-id/<id>`. TCC authorization must be granted once more for the new identity.
- Added the read-only `messages` adapter over `~/Library/Messages/chat.db` (Full Disk Access): a status-only permission probe plus newest-first, cursor-paginated recent messages with a bounded 500-char text projection; handles and IDs never leave the adapter.
- Added the read-only `phone-calls` adapter over `~/Library/Application Support/CallHistoryDB/CallHistory.storedata` (Full Disk Access): a permission probe plus recent calls with direction/time/duration/missed state; counterparty identifiers never leave the adapter.
- Added Messages and Call History to `resources`, filled the registry field descriptions/examples, and refreshed the README.

## 0.8 — 2026-08-15

- Added the Safari adapter for bounded read-only bookmark and Reading List discovery with opaque IDs, strict filters, pagination, and stale-cursor detection.
- Added guarded Reading List creation through Safari's official AppleScript (dry-run/apply, normalized-URL idempotency, bounded read-back).
- Added guarded local-only bookmark/folder CRUD with dry-run default, Safari-quit checks, atomic replacement, rollback, and read-back; writes are local-only and do not sync to iCloud.

## 0.7 — 2026-08-14

- Added the Shortcuts adapter over `/usr/bin/shortcuts` and `Shortcuts Events`: permission, bounded list/get/folders, guarded run, and folder move.
- Added guarded Cherri managed-source authoring (validate/build/create/update) with a private registry, exact confirmations, and no remote signing.
- Added guarded copy-first editing of existing Shortcuts (replace-text, append-only insert, bounded delete, bounded move) with SHA-256 concurrency guards and fail-closed outcomes.

## 0.6 — 2026-08-14

- Added a bounded read-only Notes.app Automation adapter: permission, account/nested-folder discovery, metadata query, and explicit plaintext/HTML get.
- Added guarded Notes create/rename/move/delete with a user-confirmed iCloud write-account binding, dry-run/apply, optimistic concurrency, and read-back.
- Body replacement and folder create/rename are guarded; folder move/delete apply stays fail-closed on Notes 4.13 identity/resurrection issues.

## 0.5 — 2026-08-14

- Added the public-PhotoKit Photos adapter: authorization, album hierarchy, and bounded metadata-only query/get with opt-in location.
- Added guarded single-resource export with offline and no-overwrite defaults plus explicit network opt-in.

## 0.4 — 2026-08-14

- Added the EventKit Reminders adapter: unique iCloud source selection, list discovery, bounded query/get, alarms, and recurrence.
- Added guarded create/edit/delete and complete/reopen with dry-run/apply, idempotent receipts, and read-back states.

## 0.3 — 2026-08-14

- Added the EventKit Calendar adapter: unique iCloud CalDAV source selection, bounded query/get, ISO 8601 + IANA time zones, recurrence, and opaque occurrence IDs.
- Added guarded create/edit/delete with dry-run/apply, `DELETE EVENT` confirmation, `this|future` span, alarms, and bounded conflict detection.

## 0.2 — 2026-07-23

- Added the read-only Mail adapter over the local V10 SQLite/EMLX fast path with a bounded Mail.app Apple Events fallback.
- Added doctor/accounts/mailboxes/query/get/reveal/attachments commands with opaque IDs, bounded limits, and explicit text/raw projections.

## 0.1 — 2026-07-16

- First Contacts adapter release: permission checks, iCloud container verification, count/list/get/query, and guarded create/edit/delete with external IDs, avatars, and JSON snapshot export.
