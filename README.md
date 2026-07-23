# macos-data-cli

A CLI-first macOS native data access layer for agents and developers.

Agents that need to work with macOS data often depend on fragile GUI automation,
platform-specific integrations, or private and unstable data formats.
`macos-data-cli` provides a local, scriptable, testable interface that prefers
Apple public frameworks and permits narrowly scoped, documented read-only local
adapters when no public framework exposes the required data.

## Project status

The first Contacts adapter is currently at version 0.1.7. It supports
permission checks, iCloud container verification, JSON reads, queries,
controlled writes, avatars, deletion, external ID migration, and JSON
snapshots.

Mail 0.2 is under development. Read-only capability checks, account and mailbox
discovery, bounded message-metadata queries, explicit cached text/raw reads,
Mail.app text fallback, and visual reveal are now available. The adapter uses a
runtime-verified V10 SQLite/EMLX fast path and never writes the Mail store.

Version 0.1 is the first Contacts adapter. Only commands explicitly marked as available below should be expected to work.

See the detailed roadmaps:

- [中文路线图](ROADMAP_CN.md)
- [English Roadmap](ROADMAP.md)

User documentation:

- [Usage](docs/usage.md)
- [Development Rules](docs/development/rules.md)
- [Installation](INSTALL.md)
- [Agent integration guide](AGENTS.md)
- [Changelog](CHANGELOG.md)
- [Distribution Signing TODO](docs/development/distribution-signing.md)

## Mail 0.2 development commands

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
`mail get` defaults to metadata. Text and raw reads are explicit; missing cached
text may use bounded Mail.app Apple Events, while raw stays cache-only and exact.
Raw bytes are never embedded in JSON and existing output files are not
overwritten. `mail reveal` is the only command here that intentionally activates
Mail.app. `mail attachments verify` compares SQLite and cached MIME counts only;
it never exports attachment names or payloads and treats partial EMLX as unverified.

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

The next adapter is Mail in 0.2, using a read-only local SQLite/EMLX path with
Mail.app Apple Events fallback and visual verification. Calendar moves to 0.3,
followed by Reminders, Notes, and Photos. See the
[Mail architecture decision](docs/development/mail-adapter-architecture.md).
vCard support, batch operations, and change detection remain Contacts-related
follow-up work. Each adapter should define its own authorization requirements,
data mapping, error format, and tests.

## License

See [LICENSE](LICENSE).
