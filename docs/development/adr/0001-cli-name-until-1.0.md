# ADR 0001: Keep `macos-data` until the 1.0.0 review

- Status: accepted
- Date: 2026-08-14
- Decision owner: project owner

## Context

The project audited Apple's naming guidance, the Homebrew namespace, and several
neutral candidates. `xvk-data` was explicitly rejected, and no replacement is
clearly better than the current command. Calendar 0.3 should not combine adapter
delivery with command, brand, Homebrew, and Agent migration.

## Decision

- `macos-data` remains the sole canonical command for 0.3.0 and the complete 0.x line.
- No new CLI alias or deprecation process is introduced during 0.x.
- Naming is reviewed again as a 1.0.0 release gate; this does not pre-commit the
  project to a rename.
- This decision does not change the repository, Homebrew token, app bundle
  identifier, TCC identity, diagnostics directory, `macos-data-cli` URL label,
  or `x-macos-data://external-id/` data contract.
- A new ADR may reopen the decision earlier only if concrete legal advice,
  platform policy, or an unacceptable naming collision appears.

## Consequences

Version 0.3.0 can focus on Calendar quality without migration risk. Existing
Agents, scripts, and users keep the same command. The 1.0.0 review must refresh
trademark, registry, Homebrew, domain, migration-window, alias-contract, and
rollback evidence.
