## What is mpia

`mpia` is, at its core, a local macOS data access CLI for agents and developers. It lets agents use one discoverable, machine-readable command contract without depending on a particular agent vendor or client. Under the hood, it prefers Apple public frameworks and, where none exists, narrowly scoped local adapters with fail-closed read/write boundaries. It runs locally and never uploads Contacts, Mail, Photos, or Notes.

## Install and TCC

**Homebrew Cask is the primary and strongly recommended installation path:**

```bash
brew tap xxvk/tap
brew install --cask mpia
```

The bundle identifier is `com.xvk.mpia.cli`. For protected macOS data, grant the requested Contacts, Calendar, Reminders, Photos, Full Disk Access, or Automation permission to the Homebrew-installed `mpia` app bundle. Do not substitute a raw executable when granting TCC permissions.

## macOS demo app (planned)

A SwiftUI macOS demo app is planned to provide a visual way to explore mpia permissions, resource discovery, and protected read/write flows. The CLI and its machine-readable contract remain the canonical interface.

## Other information

### Safety boundary

- Read-only commands never mutate user data.
- Writes require an explicit `--dry-run` (preview) or `--apply` (persist).
- Destructive operations require an exact confirmation phrase in addition to `--apply` (for example `DELETE CONTACT`).
- Ambiguous matches are reported, never silently selected.
- `outcome_unknown` results must never be retried automatically.

### Machine-readable contract

Every command returns JSON:

```json
{ "ok": true, "contractVersion": "0.1", "data": {} }
```

Get the command registry with:

```bash
mpia GET "/agent/manifest"
```
