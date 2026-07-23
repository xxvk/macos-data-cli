# Agent Integration Guide

This repository is a CLI, not an Agent Skill. Agents and Skills that invoke
`macos-data` should read these files before using it:

1. `README.md` or `README_CN.md` for the supported command surface
2. `docs/usage.md` or `docs/usage_CN.md` for command details and examples
3. `docs/development/rules.md` or `docs/development/rules_CN.md` for safety rules
4. `docs/development/cli-contract.md` or its Chinese version for JSON and exit codes
5. `docs/development/local-debug-and-tcc_CN.md` for local Xcode, Debug app, and
   Contacts TCC authorization behavior

For Mail 0.2 planning or implementation, also read:

6. `docs/development/mail-adapter-architecture.md` (or the Chinese summary) for
   the read-only SQLite/EMLX boundary, Apple Events fallback, permissions,
   privacy rules, and compatibility gates

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

`scripts/build_debug_app.sh` signs this bundle with
`scripts/macos-data.entitlements`. Do not remove the
`com.apple.security.automation.apple-events` entitlement: the release gate reads
it back from the signed app and fails if it is absent or false.

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

## Non-negotiable Mail rules

- Run `mail doctor` before relying on direct-store reads. Enable SQLite only
  when `fastPathAvailable` is true; never infer support from the macOS version
  or a `V10` directory alone.
- Open `Envelope Index` strictly read-only and query-only. Never write the
  database, WAL/SHM sidecars, `.emlx` files, or Mail account configuration.
- Treat account, mailbox, message, and cursor IDs as opaque adapter values. Do
  not expose or reconstruct raw account authorities or full mailbox URLs.
- Keep metadata queries bounded: default 50, maximum 200, cursor pagination,
  bound parameters, and the implementation deadline. Do not read bodies during
  `mail accounts`, `mail mailboxes`, or `mail query`.
- Use `mail get` for one opaque message ID. It defaults to metadata; body text
  requires `--content text`, and raw RFC 822 requires `--content raw --output`.
  Never put raw bytes in JSON or overwrite an existing output file.
- Preserve `partial`, `metadata_only`, `incomplete`, and `fallbackReason` exactly;
  do not present missing or partial cache content as a complete empty message.
- Missing cached text may fall back to Mail.app only for explicit `--content text`.
  Ordinary fallback must not launch Mail.app; raw RFC 822 never falls back because
  AppleScript text cannot provide a byte-exact replacement.
- `mail reveal` is an explicit visible operation that may launch and activate
  Mail.app. Do not use it as a hidden read path or claim it verifies content bytes.
- `mail attachments verify` is metadata-only validation. It may compare SQLite
  row counts with cached MIME part counts, but it must not return attachment names,
  paths, or payloads. Partial EMLX is always unverified, even when counts agree.
- Serialize Apple Events, keep the 3-second timeout and 30-second timeout circuit
  breaker, and preserve the stable Automation error categories.
- Do not render HTML with WebKit or load remote resources. The text projection
  uses bounded MIME decoding and a local HTML-to-text sanitizer.
- On the verified macOS 26.4 V10 store, `mailboxes.source` is null; account scope
  is intentionally derived from the mailbox URL scheme and authority and then
  hash-redacted. Re-probe schema behavior on every new store version.
- Use `scripts/run_mail_doctor_smoke.sh --require-fast-path` for the full
  consistency gate and `scripts/run_mail_metadata_smoke.sh` for privacy-safe
  live command validation. `scripts/run_mail_content_smoke.sh` stores one text
  and raw sample only in an auto-deleted temporary directory and prints no
  content. `scripts/run_mail_attachment_smoke.sh` prints aggregate counts only.
  None of the smoke tests writes to Mail's store.
- Use `scripts/run_mail_automation_smoke.sh --gui-session` when an agent shell is
  outside the loginwindow bootstrap namespace. It verifies Automation and one
  visible reveal without printing message fields. Add `--with-text-fallback`
  only when reading one uncached body is explicitly acceptable.

## Local verification

These checks are local-only and do not require CI:

```bash
swift test
swift build
bash scripts/run_cli_contract_tests.sh
bash scripts/run_mail_doctor_smoke.sh --require-fast-path
bash scripts/run_mail_metadata_smoke.sh
bash scripts/run_mail_content_smoke.sh
bash scripts/run_mail_attachment_smoke.sh
bash scripts/run_mail_automation_smoke.sh --gui-session
bash scripts/run_mail_release_gate.sh
```

Use `scripts/run_mail_release_gate.sh --with-automation` only for an attended
check: it performs a visible reveal and intentionally fails without retry when
Mail.app exceeds the 3-second Apple Event budget.

The contract script uses the raw Debug executable and therefore requires the
calling process to have Contacts permission. For this machine's TCC behavior,
real read verification must use the authorized `.build/debug/macos-data.app`;
see `docs/development/local-debug-and-tcc_CN.md`.

Real Contacts writes are exceptional operations and must follow the documented
fixture and explicit-authorization workflow in `docs/development/rules.md`.
