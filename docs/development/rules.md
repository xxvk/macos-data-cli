# Development Rules

## Test-driven workflow

For every feature:

1. Define the CLI behavior and JSON contract.
2. Add a failing unit or integration test.
3. Implement the smallest change that makes the test pass.
4. Run the full test suite.
5. Build a release binary, install it locally, and verify the real CLI when the feature touches macOS frameworks.
6. Update the usage documentation and roadmap status.

Tests must not create real Contacts records repeatedly. Use deterministic pure tests for mapping and matching, and keep the documented local fixtures for occasional end-to-end verification.

The real CLI integration smoke test is deliberately separate from `swift test`
and from CI. Run the safe local path with:

```bash
bash scripts/run_local_contacts_integration.sh
```

For process-level JSON contract and negative-path checks, run:

```bash
bash scripts/run_cli_contract_tests.sh
```

This suite is local-only and does not write or delete Contacts records.

Only when explicitly validating real writes, run the disposable-contact path:

```bash
bash scripts/run_local_contacts_integration.sh --with-writes
```

The write path creates and cleans up only the temporary integration contact. It
must not delete the permanent person, organization, or create smoke-test
fixtures.

## Contacts contract

- `kind` is `person` or `organization` and comes from the native Contacts record type.
- `external_id` is optional in read models but required for creation.
- The CLI must never create a contact without `external_id`; this is a permanent
  Contacts contract, not a deferred feature.
- External IDs are encoded as `x-macos-data://external-id/<id>` in the URL field.
- The reserved URL label is strictly `macos-data-cli`. Readers must not treat `Homepage` or other labels as an external ID.
- The reserved URL value is `x-macos-data://external-id/<id>`.
- `imageAvailable` is the Contacts.framework availability result; it is not a
  definitive statement about whether Contacts.app displays an iCloud avatar.
- Avatar apply responses include `avatar.status`. `readback_confirmed` means
  the saved record returned non-empty image data. `verification_unknown` means
  the save was accepted but Contacts.framework could not safely read the image
  back; follow `avatar.nextAction`, and never auto-delete or auto-recreate the
  record. Avatar writes must not be retried automatically.
- `contacts avatar verify` performs a lightweight availability preflight and
  skips `imageData` reads when the preflight is false, reducing iCloud fault risk.
- `contacts avatar replace` is the explicit recovery path for records that
  cannot be edited in place. It requires `RECREATE CONTACT`, creates a new
  Contacts record, and must never be invoked automatically.
- If a write fails with CoreData error `134092`, the CLI must treat the record as potentially corrupted, preserve diagnostic details, and tell the Agent to preserve the JSON fields, delete the record with explicit confirmation, recreate it, and retry. The CLI must never auto-delete or auto-recreate a contact.
- Apple contact identifiers are local implementation details, not cross-system IDs.
- Query fields are normalized according to their data type; combined queries use AND semantics and accept at most three distinct fields.
- Ambiguous matches must be reported; the CLI must not silently choose a record for a write.

## Safety and privacy

- Check Contacts authorization before reading or writing.
- Writes require explicit `--dry-run` or `--apply`.
- Never access the private Contacts database or upload contact data.
- Version 0.1 permits only the iCloud container; if it is unavailable, writes must fail rather than fall back to local or another account.
- Diagnostics retain `external_id` only as a correlation key. Email addresses,
  international phone numbers, absolute paths, and underlying exception text
  are redacted before being written to `~/Library/Logs/macos-data-cli/diagnostics.log`.
- Diagnostics must not include names, organizations, postal addresses, avatar
  bytes, or full JSON contact payloads.

## Codex authorization and Computer Use

- Codex should automatically perform authorization and settings flows that do
  not require a password, Apple ID entry, or security confirmation.
- This includes opening the relevant macOS Settings pane, launching the
  already-authorized local app, and accepting the explicitly requested ordinary
  permission prompt through Computer Use when the system allows it.
- Hand the flow to the user in an external Terminal or UI only when macOS asks
  for an administrator password, Apple ID credentials, a security confirmation,
  or another secret that Codex must not enter.
- Do not repeatedly ask the user to click through a flow that Codex can safely
  complete. Report the exact remaining hand-off point and the reason.
- Computer Use actions must remain within the requested app and permission
  scope. Never type, store, or expose passwords, tokens, or other credentials.

## Compatibility

The current deployment target is macOS 26.0+. Use the repository's Swift/Xcode toolchain and keep framework availability checks close to the adapter boundary.

For compatibility verification, rebuild the Release configuration before
testing the binary. A stale `.build/release/macos-data` may not contain the
latest source changes.

## Metadata (0.1)

`metadata` belongs to the JSON contract only. Contacts 0.1 does not promise to write it into Apple Contacts; it must not be silently encoded into Notes, URLs, or another field. Any future persistence requires a versioned encoding and migration rule.

Ordinary reads must not request image bytes. Avatar verification first performs
a lightweight availability preflight; avatar replacement is the explicit
recovery path for records that cannot safely be edited in place.
