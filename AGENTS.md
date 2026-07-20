# Agent Integration Guide

This repository is a CLI, not an Agent Skill. Agents and Skills that invoke
`macos-data` should read these files before using it:

1. `README.md` or `README_CN.md` for the supported command surface
2. `docs/usage.md` or `docs/usage_CN.md` for command details and examples
3. `docs/development/rules.md` or `docs/development/rules_CN.md` for safety rules
4. `docs/development/cli-contract.md` or its Chinese version for JSON and exit codes
5. `docs/development/local-debug-and-tcc_CN.md` for local Xcode, Debug app, and
   Contacts TCC authorization behavior

## Current development executable

During local development, use the Debug app workflow described in
`docs/development/local-debug-and-tcc_CN.md`. Build the app with:

```text
bash scripts/build_debug_app.sh
```

The resulting authorized app is:

```text
.build/debug/macos-data.app
```

For pure unit tests, `.build/debug/macos-data` remains available. Skills should
allow the executable/app path to be configured with `MACOS_DATA_CLI`; they must
not assume a Homebrew or Release binary while development is in progress.

## Non-negotiable Contacts rules

- Contacts writes target the verified iCloud container only.
- Every CLI-created contact must have `external_id`.
- The external ID is stored only as URL label `macos-data-cli` with value
  `x-macos-data://external-id/<id>`.
- Regular edit cannot change `external_id`; use the migration command.
- Writes require `--dry-run` or explicit `--apply`.
- Delete requires `--confirm "DELETE CONTACT"`.
- JSON responses use contract version `0.1`; branch on the process exit code first.
- Do not use `imageAvailable` as definitive GUI truth for iCloud avatars. For
  avatar writes, use `data.avatar.status`: `readback_confirmed` is strong
  confirmation; `verification_unknown` means the save was accepted but the
  framework could not read the image back. Follow `avatar.nextAction`; never
  auto-retry, delete, or recreate a contact.
- For a read-only existing-avatar check, use `contacts avatar verify --external-id`;
  interpret `readback_confirmed`, `not_available`, and `verification_unknown`.
- Ambiguous matches must be reported, never silently selected.
- `metadata` is preserved in JSON but is not written to Contacts in 0.1.

## Local verification

These checks are local-only and do not require CI:

```bash
swift test
swift build
bash scripts/run_cli_contract_tests.sh
```

The contract script uses the raw Debug executable and therefore requires the
calling process to have Contacts permission. For this machine's TCC behavior,
real read verification must use the authorized `.build/debug/macos-data.app`;
see `docs/development/local-debug-and-tcc_CN.md`.

Real Contacts writes are exceptional operations and must follow the documented
fixture and explicit-authorization workflow in `docs/development/rules.md`.
