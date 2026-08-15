## What is mpia

`mpia` is a local, scriptable macOS data access layer for agents and developers. It prefers Apple public frameworks and, where none exists, narrowly scoped local adapters with fail-closed read/write boundaries. It runs locally and never uploads Contacts, Mail, Photos, or Notes.

## Safety boundary

- Read-only commands never mutate user data.
- Writes require an explicit `--dry-run` (preview) or `--apply` (persist).
- Destructive operations require an exact confirmation phrase in addition to `--apply` (for example `DELETE CONTACT`).
- Ambiguous matches are reported, never silently selected.
- `outcome_unknown` results must never be retried automatically.

## Adapters

Contacts, Mail (read-only), Calendar, Reminders, Photos, Notes, Shortcuts, and Safari each maintain explicit permission and read/write boundaries.

## Install and TCC

The bundle identifier is `com.xvk.mpia.cli`. After the 0.9.0 rename from `macos-data`, macOS treats it as a new app: Contacts, Calendar, Reminders, Photos, Full Disk Access, and Automation must be granted once more. For TCC-authorized reads, run the signed app bundle, not the raw binary.

## Machine-readable contract

Every command returns JSON: `{ "ok": true, "contractVersion": "0.1", "data": … }`. The command registry is available via `mpia manifest --format json`.
