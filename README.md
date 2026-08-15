# macos-data-cli

A CLI-first macOS native data access layer for agents and developers.

Agents that need to work with macOS data often depend on fragile GUI automation,
platform-specific integrations, or private and unstable data formats.
`macos-data-cli` provides a local, scriptable, testable interface that prefers
Apple public frameworks and permits narrowly scoped, documented local adapters
with fail-closed read/write boundaries when no public framework exposes the
required data.

## Quick Start

Build from source and request the first read-only JSON snapshot:

```bash
git clone https://github.com/xxvk/macos-data-cli.git
cd macos-data-cli
export DEVELOPER_DIR="$(xcode-select -p)"
swift build
.build/debug/macos-data resources --format json
```

Requirements: macOS 26 or newer, Apple Silicon, and Xcode with Swift 6.2.
The public binary is not yet Developer ID signed or notarized. See
[Installation](INSTALL.md) before installing a Release binary or configuring
macOS permissions.

## Usage

Start with capability and permission checks; these commands do not modify user
data. The examples use an installed `macos-data`; from the source checkout, use
`.build/debug/macos-data` instead:

```bash
macos-data resources --format json
macos-data contacts permission
macos-data mail doctor --format json
```

Commands that can write use explicit dry-run/apply paths, and destructive
operations require an additional confirmation phrase. See the full
[command guide](docs/usage.md), [safety rules](docs/development/rules.md), and
[stable JSON contract](docs/development/cli-contract.md).

## Project status

The current source release is 0.8.1. The Contacts adapter introduced through 0.1.7 supports
permission checks, iCloud container verification, JSON reads, queries,
controlled writes, avatars, deletion, external ID migration, and JSON
snapshots.

Mail 0.2 provides read-only capability checks, account and mailbox
discovery, bounded message-metadata queries, explicit cached text/raw reads,
Mail.app text fallback, and visual reveal are now available. The adapter uses a
runtime-verified V10 SQLite/EMLX fast path and never writes the Mail store.

Version 0.2.0 added the Mail adapter while retaining the Contacts command surface.

Version 0.3.0 adds Calendar through EventKit full-access
authorization, unique iCloud CalDAV source selection, calendar/event queries,
ISO 8601 time zones, recurrence rules, opaque occurrence IDs, and dry-run/apply
paths for create/edit/delete are implemented. Local read and dry-run smoke tests
pass; the explicitly authorized disposable-event apply integration also passed
and verified final absence. The public precompiled distribution may still lag the source tag.

Reminders 0.4 adds permission/list discovery, bounded
query/get, guarded CRUD, completion/reopen, alarms and recurrence. Disposable
basic and recurring iCloud gates passed with zero fixture residue.

Photos 0.5 adds PhotoKit authorization, album discovery, bounded metadata-only
asset query/get, opaque identifiers, limited-library semantics, and guarded
single-resource export with offline and no-overwrite defaults.

Notes 0.6 adds a bounded, read-only Notes.app Automation adapter for permission
status, account and nested-folder discovery, metadata query, explicit
plaintext/HTML reads, and attachment metadata. It does not access private Notes
stores. Notes 0.6.1 adds guarded create/rename/move behind a
locally bound, user-confirmed iCloud account, dry-run/apply, concurrency checks,
privacy-safe hashes, and immediate read-back. Body replacement, attachment
mutation, delete, and folder CRUD remain unsupported in released 0.6.1. Notes
0.6.2 adds guarded `notes edit-body` for simple,
attachment-free content plus folder create/rename and guarded move/empty-folder-delete previews with opaque selectors,
hash/parent guards, cycle protection, and privacy-safe output. The disposable
signed-app body-edit gate passed with hash-confirmed read-back and zero fixture
residue. The folder gate passed create/rename; Notes 4.13 move apply proved
identity-unsafe and is disabled with a stable fail-closed error. The signed-app disposable
iCloud note create/rename/move/read-back gate passed with zero test-note residue.
Empty-folder delete preview validates fresh name/parent/emptiness state, but its
real Notes 4.13 gate invalidated the metadata graph and the child later
reappeared under a new opaque ID. Apply is therefore disabled fail-closed.
The current source also includes guarded single-note soft deletion to
Notes Recently Deleted, requiring the latest modification date and exact
`DELETE NOTE` confirmation. Permanent deletion remains UI-only, and the
signed-app soft-delete gate passed: after explicit action-time approval, only
the disposable fixture was permanently removed through Notes UI, an unrelated
Recently Deleted note was preserved, and the final signed-app query returned
zero sentinel matches.

Shortcuts 0.7.0 uses the system `/usr/bin/shortcuts`
command and public `Shortcuts Events` scripting dictionary. Permission,
bounded list/get/folders, guarded run, and folder move are implemented. The
synthetic TDD suite and disposable live gate pass: exact text output, move
preview, move apply/read-back, restoration, and zero fixture residue were all
verified. The adapter also starts the on-demand Shortcuts Events helper for cold
commands and captures plaintext output from the system CLI's stdout. It neither
reads action graphs nor accesses the private Shortcuts database.
The development tree now includes guarded 0.7.1 managed-source validate, build,
create, update, private registry/receipt, and managed-forget code. Create/update
remain preview-only unless their exact confirmation is supplied, and arbitrary
existing shortcuts cannot be adopted. The disposable create/run/retain-old
update/run/cleanup gate passed on macOS 27 Beta 5 with Cherri 2.3.0 and left
zero fixture/registry residue. Public action counts were `0` for both working
imports, so compiled and observed counts are separate and same-name replace
fails closed when they differ.
The development tree now also includes guarded 0.7.2 existing-object editing:
`shortcuts edit inspect` safely classifies one local `.cherri` or `.shortcut`
without importing, opening, storing, or echoing its content. Opaque/signed
artifacts, unknown actions, nested magic-variable/attachment structures,
suspected secrets, and device-bound references fail closed to manual migration.
Input is local-file-only: iCloud share links and other URI inputs are rejected
before reading, with no download, redirect, clipboard, or import path.
For eligible unsigned artifacts, `shortcuts edit plan` validates a strict,
SHA-256-guarded sequence of `insert_text`, `replace_text`, `delete_action`, and
`move_action` operations against an in-memory shadow graph. It returns only a
redacted plan and never writes Shortcuts.app. A replace-only plan, or an
append-only `insert_text` plan whose graph already contains a Text action, or a
bounded all-`delete_action` plan that leaves at least one action, may use
`shortcuts edit copy`: dry-run performs no AX read, while apply requires the
exact visible editor-name SHA-256 and `EDIT SHORTCUT COPY`, duplicates the
original, changes only resolver-approved Text values, and verifies every step.
Append insertion uses exact `duplicateAction:` and is allowed only at the graph
end. Delete presses only the resolver-bound Close button and waits for the exact
smaller graph. A bounded all-`move_action` plan is now copy-first apply-capable:
each adjacent reorder uses an exact menu identifier and complete visual-order
read-back. Middle/no-source insert, mixed-operation plans, same-index moves, and
semantically indistinguishable adjacent actions remain rejected.
`shortcuts edit ui-inspect` adds bounded,
read-only AX structure discovery: it does not prompt, activate, click, type, or
return labels/titles/identifiers, and it always reports apply as disabled.
Its disposable macOS 27 Beta 5 gate calibrated the exact
`editor.shortcutname` marker, found one redacted candidate, then deleted the
fixture and confirmed zero search/candidate residue.
An internal copy-first mutation coordinator is TDD-covered as a design
boundary: it requires exact confirmation, preflights the whole plan, proves a
distinct graph-identical recovery copy, and reads back every step.
The design now also binds the redacted plan to a non-Codable private in-memory
execution plan and a recovery-first, exact-sequence guarded bridge. Concrete
debug-only macOS 27 gates have proved copy-first Text replacement, append-only
Text insertion, and bounded action deletion, including hash read-back, unchanged
remaining actions, and unchanged originals. Arbitrary-position insert and move
remain unavailable. All gate fixtures were explicitly deleted with zero residue.

Safari 0.8 adds bounded bookmark and Reading List discovery from Safari's
property-list snapshot, opaque IDs, strict queries, stale-cursor detection, and
guarded Reading List creation. The next local CRUD slice adds bookmark and
folder create/edit/move/delete with dry-run by default, an optimistic source
hash, Safari-quit checks, private recovery, atomic replacement, rollback, and
read-back. These plist mutations are explicitly local-only and do not sync to
iCloud; synchronization research is deferred to 0.8.8.

See the detailed roadmaps:

- [中文路线图](ROADMAP_CN.md)
- [English Roadmap](ROADMAP.md)

User documentation:

- [Usage](docs/usage.md)
- [Development Rules](docs/development/rules.md)
- [Installation](INSTALL.md)
- [Agent integration guide](AGENTS.md)
- [Shortcuts 0.7.1 authoring boundary](docs/development/shortcuts-authoring.md)
- [Shortcuts 0.7.2 existing-editing boundary](docs/development/shortcuts-existing-editing.md)
- [Safari 0.8 architecture and direct-plist feasibility gate](docs/development/safari-adapter-architecture.md)
- [Changelog](CHANGELOG.md)
- [Distribution Signing TODO](docs/development/distribution-signing.md)
- [Calendar 0.3 architecture](docs/development/calendar-adapter-architecture.md)
- [Photos 0.5 architecture](docs/development/photos-adapter-architecture.md)
- [Notes 0.6 feasibility decision](docs/development/notes-adapter-feasibility.md)

## Mail 0.2 commands

```text
macos-data mail doctor --format json
macos-data mail accounts --format json
macos-data mail mailboxes [--account-id <id>] --format json
macos-data mail query [filters] [--limit <1...200>] [--cursor <cursor>] --format json
macos-data mail get --id <id> [--content metadata|text] --format json
macos-data mail get --id <id> --content raw --output <file|->
macos-data mail reveal --id <id> --format json
macos-data mail attachments verify --id <id> --format json
```

`doctor` does not launch Mail.app, prompt for permission, or read message
subjects, addresses, or bodies. `fastPathAvailable` is true only after the V10
required structure, WAL, and read-only database checks pass at runtime.
Metadata queries default to 50 rows and are capped at 200. They use bound SQL
parameters, opaque local IDs, cursor pagination, and a query deadline; message
bodies are not read.
If the V10 schema/FDA fast path is unavailable but Mail.app is already running
and Automation is authorized, accounts, top-level mailboxes, and message
metadata use a five-second bounded Mail.app fallback. It inspects at most 32
accounts, 200 mailboxes, and 25 message candidates; queries are always marked
`incomplete`, provide no cursor, and return separate `appmsg_` opaque IDs.
`mail get` defaults to metadata. Text and raw reads are explicit; missing cached
text may use bounded Mail.app Apple Events, while raw stays cache-only and exact.
Raw bytes are never embedded in JSON and existing output files are not
overwritten. `mail reveal` is the only command here that intentionally activates
Mail.app. `mail attachments verify` compares SQLite and cached MIME counts only;
it never exports attachment names or payloads and treats partial EMLX as unverified.
Raw export and attachment verification never use the metadata fallback.

### Mail 0.2 safety boundary

Mail 0.2 is intentionally read-only. It does not send, draft, reply, forward,
move, archive, delete, flag, mark, or modify messages, mailboxes, accounts, or
Mail preferences. Unsupported write-like commands must return a usage error
before any Mail store or Mail.app access occurs. This boundary is part of the
0.2.0 contract and may only change in a separately specified release.

## Calendar 0.3 commands

```text
macos-data calendar permission
macos-data calendar sources --format json
macos-data calendar calendars --format json
macos-data calendar query --start <iso8601> --end <iso8601> --format json
macos-data calendar conflicts --start <iso8601> --end <iso8601> --format json
macos-data calendar get --id <opaque-event-id> --format json
macos-data calendar create --input event.json --dry-run|--apply [--idempotent] --format json
macos-data calendar edit --id <id> --input patch.json --dry-run|--apply [--span this|future] --format json
macos-data calendar delete --id <id> --dry-run [--span this|future] --format json
macos-data calendar delete --id <id> --apply --confirm "DELETE EVENT" [--span this|future] --format json
```

The adapter defaults only to the uniquely verified iCloud CalDAV source and
does not fall back to Local, Exchange, or another account. Event, source,
calendar, and cursor IDs are local opaque values. Recurring edit/delete requires
an explicit `this` or `future` span. Attendees are readable but not writable in
0.3. Timed events use ISO 8601 timestamps; all-day events use `YYYY-MM-DD` start
and exclusive end dates. Relative/absolute alarms can be read, written, replaced,
or cleared. See the [Calendar architecture](docs/development/calendar-adapter-architecture.md).

## Goals

- Work through the Terminal and remain easy for scripts and agents to invoke
- Provide a stable CLI and JSON contract
- Let different agents share one CLI without coupling to Codex, Claude Code, or another platform
- Prefer Apple public frameworks over GUI automation
- Make writes explicit with dry-runs, diffs, and confirmation
- Run locally without uploading contacts or other system data
- Expand through independent adapters for macOS data services

Obsidian is the author's current use case, not a required part of the public contract. External systems may use their own stable identifiers.

## 0.1 scope: Contacts adapter

The first version distinguishes personal and organization contacts through an explicit `kind` field (`person` or `organization`) and plans to support controlled reads and writes, including:

- Names, organizations, departments, and roles
- Phonetic given and family names
- Email addresses, phone numbers, URLs, and postal addresses
- Contact images
- A required `external_id` for every CLI-created contact
- Multi-factor matching using organization names, emails, phone numbers, and other available data
- JSON input and output
- `--dry-run` and explicit `--apply`

Avatar apply responses include a verification status. `readback_confirmed`
means the saved record returned non-empty image data; `verification_unknown`
means the save was accepted but the Contacts framework could not safely read
the image back. `imageAvailable` is not definitive GUI truth for iCloud avatars.

If a query matches multiple contacts, the CLI returns an ambiguous result and refuses an automatic write. The calling agent must inspect the results and decide what to do next.

Currently available:

```text
macos-data contacts permission
macos-data contacts count [--format json]
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
macos-data contacts query --name "..."
macos-data contacts query --kind organization
macos-data contacts query --phone "..."
macos-data contacts query --email "..."
macos-data contacts query --url "..."
macos-data contacts query --organization "..."
macos-data contacts query --postal-code "..."
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
cat contact.json | macos-data contacts create --stdin --dry-run
cat contact.json | macos-data contacts create --stdin --apply --idempotent
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
cat patch.json | macos-data contacts edit --external-id <id> --stdin --dry-run
macos-data contacts edit --external-id <id> --image <file> --dry-run
macos-data contacts edit --external-id <id> --image <file> --apply
macos-data contacts avatar verify --external-id <id> --format json
macos-data contacts avatar replace --external-id <id> --image <file> --dry-run
macos-data contacts avatar replace --external-id <id> --image <file> --apply --confirm "RECREATE CONTACT"
macos-data contacts delete --external-id <id> --dry-run
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT" --ignore-not-found
macos-data contacts external-id migrate --from <old> --to <new> --dry-run
macos-data contacts external-id migrate --from <old> --to <new> --apply --confirm "CHANGE EXTERNAL ID"
macos-data contacts export --format json [--output <file>]
```

Query conditions use AND semantics. A query accepts at most three conditions, and each field can appear only once. `--format json` does not count as a condition.

Machine-readable responses use JSON contract version `0.1`, independent of the
CLI release version. Envelope responses contain `ok`, `contractVersion`, and
either `data` or `error`.
See [the detailed CLI contract](docs/development/cli-contract.md) for stable
exit codes and error codes.

Current limitations and remaining 0.1 work:

```text
- The verified iCloud container is selected by default; `--container iCloud`
  or the exact iCloud container identifier may be used explicitly
- `--idempotent` is opt-in for create retries; a different persisted payload
  with the same external ID remains an error
- `--ignore-not-found` is opt-in for delete retries
- Real CLI CRUD integration tests remain local-only and are not run by `swift test`
- vCard import/export, batch operations, and change detection are not implemented
```

## Boundaries

- Do not copy or redistribute Apple SDKs or Apple binaries
- Do not access the internal Contacts database directly
- Do not use Apple private APIs
- Do not make GUI automation, screen coordinates, or AppleScript the core write path
- Mail 0.2 has one documented exception for strictly read-only access to Mail's
  local index and cached message files because no public framework exposes
  general mailbox enumeration. The adapter must validate the schema, fail
  closed, and never write those files.
- Do not treat an Apple contact identifier as a cross-system stable key
- Do not upload contacts, addresses, phone numbers, or images
- Do not include a built-in AI agent
- Do not make Obsidian a required part of the public data contract

## Platform

The planned minimum deployment target is macOS 26.0+. The project uses Swift Package Manager and prefers Apple public frameworks.

Contacts access requires user authorization. The CLI should check and explain authorization status and require explicit confirmation before writes.

See [`docs/development/distribution-signing.md`](docs/development/distribution-signing.md) for the Homebrew update, Gatekeeper, quarantine, and local release verification workflow.

## Future direction

Calendar 0.3, Reminders 0.4, Photos 0.5, and the bounded read-only Notes 0.6
source releases are complete. Guarded Notes create/rename/move writes are
assigned to 0.6.1. Notes integration is Automation rather than a native Notes
Framework and must not access private Notes stores. `macos-data` remains the canonical command through
0.x; naming is reviewed again before 1.0.0.
The current Reminders development slice supports full-access discovery,
bounded query/get, and guarded `create --dry-run|--apply` with read-back states
and optional short-lived idempotency. Partial edit and guarded single-item delete
are implemented; complete/reopen include safe repeated no-ops and passed
real-write verification. The automatic cleanup gate is implemented. The disposable
create/get/edit/complete/reopen/delete gate
passed against local iCloud with final matching count zero. See
[Reminders usage](docs/usage.md).
Photos currently exposes permission/resource discovery, bounded album pages,
metadata-only asset query/get with location opt-in, and guarded single-resource
export with offline/no-overwrite defaults. See the
[Photos architecture](docs/development/photos-adapter-architecture.md).
Mail 0.2 uses a read-only local SQLite/EMLX path with Mail.app Apple Events
fallback and visual verification. See the
[Mail architecture decision](docs/development/mail-adapter-architecture.md).
vCard support, batch operations, and change detection remain Contacts-related
follow-up work. Each adapter should define its own authorization requirements,
data mapping, error format, and tests.

## Community

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing behavior or contract changes.
- Report vulnerabilities through the private path described in [SECURITY.md](SECURITY.md).
- Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

See [LICENSE](LICENSE).
