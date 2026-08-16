---
name: mpia
description: Use mpia (the macOS native data access CLI, command `mpia`) to read or, with explicit authorization, mutate local macOS data — Contacts, Mail, Calendar, Reminders, Photos, Notes, Shortcuts, Safari. Trigger when the task needs macOS system data, personal data, or a native app capability, instead of GUI automation, screen coordinates, or private APIs.
---

# mpia — macOS personal intelligent access for AI agents

`mpia` is a local, scriptable macOS data layer with a stable JSON contract. It
prefers Apple public frameworks and, where none exists, narrowly scoped local
adapters with fail-closed read/write boundaries. It runs locally and never
uploads Contacts, Mail, Photos, or Notes.

## Two ways to call it

1. **Typed tools (preferred).** When the `mpia_*` dynamic tools are mounted in
   this session (`mpia_manifest`, `mpia_resources`, `mpia_contacts_*`,
   `mpia_mail_doctor`, …), prefer them: they carry typed parameters and the
   safety semantics below. Call `mpia_manifest` to list the full registry.
2. **Direct CLI.** For anything the tools do not cover, run the binary. Do not
   assume a Homebrew/Release install during development; honor `MPIA_CLI`
   (raw binary) and `MPIA_APP` (signed app bundle) if set. The signed bundle
   executable is `.build/debug/mpia.app/Contents/MacOS/mpia` and carries the
   TCC identity `com.xvk.mpia.cli`.

Every command returns JSON: `{ "ok": true, "contractVersion": "0.1", "data": … }`
on success, or `{ "ok": false, "error": { "code", "message" } }` on failure.
Branch on the process exit code first, then `error.code`.

## Non-negotiable safety rules

- **Read before write.** Read-only commands never mutate. Writes require an
  explicit `--dry-run` (preview) or `--apply` (persist). Never add `--apply`
  yourself unless the user has explicitly authorized that specific mutation.
- **Destructive commands need the exact confirmation phrase** in addition to
  `--apply` (e.g. `DELETE CONTACT`, `DELETE EVENT`, `DELETE REMINDER`,
  `DELETE NOTE`). Never auto-supply a confirmation phrase.
- **Never auto-retry** `outcome_unknown` or `save_accepted_readback_pending`.
  A pending/unknown result means "inspect, do not blindly repeat".
- **Ambiguous matches are reported, never silently selected.** If `query` finds
  multiple candidates, show the user the options; do not guess.
- **IDs are opaque.** `external-id`, `calevent_`, `reminder_`, `acct_`, cursor
  and folder IDs are machine-local and may be rewritten. Do not parse them or
  treat them as stable across devices.
- **Bound queries.** Paginate with `limit`/`cursor`; default page is 50, max 200.

## Adapter boundaries (what is writable)

| Adapter | Read | Write |
|---|---|---|
| Contacts | ✅ | guarded CRUD (dry-run/apply + confirm) |
| Mail | ✅ | ❌ read-only (never writes the store) |
| Calendar | ✅ | guarded CRUD (full-access + confirm) |
| Reminders | ✅ | guarded CRUD (full-access + confirm) |
| Photos | metadata ✅ | guarded single-resource export (no network by default) |
| Notes | ✅ (Automation) | guarded subset (create/rename/soft-delete) |
| Shortcuts | ✅ | guarded run/authoring (Cherri SSOT only) |
| Safari | ✅ | guarded local-only plist CRUD |

## Identity, permissions, and TCC

- Bundle identifier is `com.xvk.mpia.cli`. After the 0.9.0 rename from
  `macos-data`, macOS treats it as a **new app**: Contacts, Calendar, Reminders,
  Photos, Full Disk Access, and Automation must be granted once more.
- For real (TCC-authorized) reads, run the **signed app bundle** through
  LaunchServices, not the raw SPM binary. Set `MPIA_APP` to the bundle path when
  a smoke script requires it.
- Contacts `external_id` is stored as a URL with label `mpia-cli` and value
  `mpia://ext-id/<id>`.

## Reference

- Command registry (the single source of truth for tools and docs):
  `mpia manifest --format json`
- Repo rules: `AGENTS.md`, `docs/development/rules.md`
- JSON + exit codes: `docs/development/cli-contract.md`
