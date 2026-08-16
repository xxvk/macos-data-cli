# mpia-cli

A local, scriptable macOS data access layer for agents and developers.

[Interactive docs](https://mpia-cli-doc.vercel.app/) ·
[简体中文 README](README_CN.md) ·
[Installation](INSTALL.md) ·
[Roadmap](ROADMAP.md)

Agents that need macOS data usually depend on fragile GUI automation,
platform-specific integrations, or private data formats. `mpia` prefers Apple
public frameworks and, where none exists, uses narrowly scoped local adapters
with fail-closed read/write boundaries. It runs locally and never uploads your
data.

## Adapters

`mpia` ships ten adapters, each with independent REST-style routes and its own
permission model:

| Adapter | Command | Data source / framework | Access |
| --- | --- | --- | --- |
| Contacts | `contacts` | Contacts (iCloud container) | read + guarded write |
| Mail | `mail` | local SQLite/EMLX + Apple Events fallback | read-only |
| Calendar | `calendar` | EventKit (iCloud CalDAV) | read + guarded write |
| Reminders | `reminders` | EventKit (iCloud CalDAV) | read + guarded write |
| Photos | `photos` | PhotoKit | read + guarded export |
| Notes | `notes` | Notes.app Apple Events | read + guarded write |
| Shortcuts | `shortcuts` | `/usr/bin/shortcuts` + Shortcuts Events | run + guarded author/edit |
| Safari | `safari` | Bookmarks.plist + Apple Events | read + guarded local CRUD |
| Messages | `messages` | `chat.db` SQLite (Full Disk Access) | read-only |
| Phone calls | `phone-calls` | `CallHistory.storedata` (Full Disk Access) | read-only |

See [Usage](docs/usage.md) for per-adapter command details and examples.

## Quick start

Build from source and request the first read-only resource snapshot:

```bash
git clone https://github.com/xxvk/mpia-cli.git
cd mpia-cli
export DEVELOPER_DIR="$(xcode-select -p)"
swift build
.build/debug/mpia OPTIONS "/resources"
```

Requirements: macOS 26 or newer, Apple Silicon, and Xcode with Swift 6.2.

## Install

The public binary is not yet Developer ID signed or notarized, so
build-from-source is the reliable path today. See [Installation](INSTALL.md)
for the full workflow and the unsigned distribution boundary. The planned
Homebrew flow is:

```bash
brew tap xxvk/tap
brew install --cask mpia
```

Protected data (Contacts, Calendar, Reminders, Photos, Full Disk Access,
Automation) must be authorized for the installed app bundle
(`com.xvk.mpia.cli`), never for a raw executable.

## Usage

Start with capability and permission checks — they never modify data:

```bash
mpia OPTIONS "/resources"
mpia OPTIONS "/contacts/permission"
mpia OPTIONS "/mail/doctor"
mpia GET "/phone-calls/recent" --params '{"limit":5}'
```

Every command returns the same JSON envelope:

```json
{ "ok": true, "contractVersion": "0.1", "data": {} }
```

Get the complete machine-readable command registry with:

```bash
mpia GET "/agent/manifest"
```

Business commands use `mpia METHOD "/path" [--params JSON] [--body JSON]`.
Inline JSON may be retained in shell history or process arguments; never use it
for API keys, passwords, or other secrets.

## Safety model

- Read-only commands never mutate user data.
- Writes require an explicit `--dry-run` (preview) or `--apply` (persist).
- Destructive operations require an exact confirmation phrase (for example
  `DELETE CONTACT`) in addition to `--apply`.
- Ambiguous matches are reported, never silently selected.
- `outcome_unknown` results are never retried automatically.
- Everything runs locally; contacts, mail, photos, and other data are never
  uploaded.

## Project status

The source ships all ten adapters above and the machine-readable contract. The
current focus is 1.0.0 — product polish: documentation, Developer ID
signing/notarization, and a demo app. See [ROADMAP.md](ROADMAP.md) and
[CHANGELOG.md](CHANGELOG.md) for details.

## Documentation

- [Usage](docs/usage.md) — per-adapter command details and examples
- [Development rules](docs/development/rules.md) — safety rules
- [CLI contract](docs/development/cli-contract.md) — JSON envelope and exit codes
- [Agent integration guide](AGENTS.md)
- [Roadmap](ROADMAP.md) · [中文路线图](ROADMAP_CN.md)
- [Architecture decisions](docs/development/) — per-adapter design notes

## Goals

- Work through the Terminal and stay easy for scripts and agents to invoke
- Provide a stable CLI and JSON contract
- Let different agents share one CLI without coupling to a specific platform
- Prefer Apple public frameworks over GUI automation
- Make writes explicit with dry-runs and confirmation
- Run locally without uploading user data
- Expand through independent adapters

Obsidian is the author's current use case, not a required part of the public
contract. External systems may use their own stable identifiers.

## Boundaries

- Do not copy or redistribute Apple SDKs or Apple binaries.
- Do not use Apple private APIs, or GUI/screen-coordinate automation as the
  core write path.
- Do not access internal Apple databases directly. Documented exceptions exist
  only where no public framework exposes the data: Mail's read-only local
  index/EMLX, Messages `chat.db`, and Call History `CallHistory.storedata`.
  Each adapter verifies the schema at runtime, fails closed, and never writes
  those files.
- Do not treat an Apple contact identifier as a cross-system stable key.
- Do not upload contacts, addresses, phone numbers, images, or other user data.
- Do not include a built-in AI agent.
- Do not make Obsidian a required part of the public data contract.

## Platform

macOS 26.0 or newer, built with Swift Package Manager, preferring Apple public
frameworks.

## Community

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing behavior or contract changes.
- Report vulnerabilities through the private path described in [SECURITY.md](SECURITY.md).
- Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

See [LICENSE](LICENSE).
