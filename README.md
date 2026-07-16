# macos-data-cli

A CLI-first macOS native data access layer for agents and developers.

Agents that need to work with macOS data often depend on fragile GUI automation, platform-specific integrations, or private and unstable data formats. `macos-data-cli` aims to provide a local, scriptable, testable interface built on Apple public frameworks.

## Project status

The first Contacts adapter is available as version 0.1.0. It supports permission checks, iCloud container verification, JSON reads, queries, controlled writes, avatars, deletion, and JSON snapshots.

Version 0.1 is the first Contacts adapter. Only commands explicitly marked as available below should be expected to work.

See the detailed roadmaps:

- [中文路线图](ROADMAP_CN.md)
- [English Roadmap](ROADMAP.md)

User documentation:

- [Usage](docs/usage.md)
- [Development Rules](docs/development/rules.md)
- [Installation](../../../INSTALL.md)
- [Changelog](CHANGELOG.md)
- [Distribution Signing TODO](docs/development/distribution-signing.md)

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
- Email addresses, phone numbers, URLs, and postal addresses
- Contact images
- An optional `external_id`
- Multi-factor matching using organization names, emails, phone numbers, and other available data
- JSON input and output
- `--dry-run` and explicit `--apply`

If a query matches multiple contacts, the CLI should return an ambiguous result and refuse an automatic write. The calling agent can inspect the result and decide what to do next.

Currently available:

```text
macos-data contacts permission
macos-data contacts count
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
macos-data contacts query --name "..."
macos-data contacts query --phone "..."
macos-data contacts query --email "..."
macos-data contacts query --url "..."
macos-data contacts query --organization "..."
macos-data contacts query --postal-code "..."
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
```

Query conditions use AND semantics. A query accepts at most three conditions, and each field can appear only once. `--format json` does not count as a condition.

Planned command examples:

```text
macos-data contacts list --format json
macos-data contacts get --query '{...}' --format json
macos-data contacts create --input contact.json --dry-run
macos-data contacts update --input contact.json --apply
macos-data contacts export --format vcard
```

Update and export commands are not implemented yet. Creating a contact requires an explicit `--dry-run` or `--apply` and requires an `external_id`.

## Boundaries

- Do not copy or redistribute Apple SDKs or Apple binaries
- Do not access the internal Contacts database directly
- Do not use Apple private APIs
- Do not make GUI automation, screen coordinates, or AppleScript the core write path
- Do not treat an Apple contact identifier as a cross-system stable key
- Do not upload contacts, addresses, phone numbers, or images
- Do not include a built-in AI agent
- Do not make Obsidian a required part of the public data contract

## Platform

The planned minimum deployment target is macOS 26.0+. The project uses Swift Package Manager and prefers Apple public frameworks.

Contacts access requires user authorization. The CLI should check and explain authorization status and require explicit confirmation before writes.

## Future direction

Future versions may add vCard support, batch operations, and change detection, followed by adapters for Calendar, Reminders, Notes, Mail, and other Apple public frameworks. Each adapter should define its own authorization requirements, data mapping, error format, and tests.

## License

See [LICENSE](LICENSE).
