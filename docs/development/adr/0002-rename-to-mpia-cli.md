# ADR 0002: Rename to `mpia-cli` before 1.0.0

- Status: accepted
- Date: 2026-08-16
- Decision owner: project owner
- Supersedes: ADR 0001 (which retained `macos-data` for the 0.x line)

## Context

ADR 0001 retained `macos-data` as the canonical command through 0.x and scheduled
a naming review as a 1.0.0 release gate. The project is still pre-1.0 with no
public install base, so this is the cheapest point to change identity rather than
migrating users later. A new name was selected to be distinctive, searchable, and
free of Apple marks, the Intel trademark, and the `mpi` (Message Passing Interface)
collision.

## Decision

- The repository is renamed from `macos-data-cli` to `mpia-cli`.
- The canonical command is `mpia`, backronym "My-Mac Private Info Access".
- The bundle identifier becomes `com.xvk.mpia.cli` (`xvk` remains the reverse-DNS
  owner, not the product name).
- The Contacts external-ID scheme becomes `mpia://ext-id/<id>` and the reserved
  URL label becomes `mpia-cli`.
- On-disk state moves to `~/Library/Application Support/mpia-cli/` and
  `~/Library/Logs/mpia-cli`; the Safari opaque seed becomes `mpia-safari-v1:`.
- No compatibility alias is introduced: `macos-data` is not retained. This is
  acceptable only because there is no released install base to break.
- This supersedes ADR 0001's "keep `macos-data` through 0.x" decision.

## Consequences

- `macos-data`-written Contacts records (label `macos-data-cli`, value
  `x-macos-data://external-id/<id>`) are no longer resolved after the switch and
  must be re-created or migrated by hand. Existing data was assessed as disposable
  test fixtures.
- The bundle-ID change makes macOS treat the binary as a new app, so every
  adapter's TCC authorization must be granted once more.
- Old idempotency receipts, the Shortcuts managed registry, and the Notes
  write-account binding under the old `macos-data-cli` directory become orphans
  and must be re-created/re-bound.
- Homebrew token, GitHub repository, and the XVK_PM submodule must be updated to
  the new name in a later distribution step.
