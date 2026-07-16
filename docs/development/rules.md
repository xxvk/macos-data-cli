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

## Contacts contract

- `kind` is `person` or `organization` and comes from the native Contacts record type.
- `external_id` is optional in read models but required for creation.
- External IDs are encoded as `x-macos-data://external-id/<id>` in the URL field.
- The reserved URL label is `macos-data-cli`; readers remain compatible with older records labeled `Homepage`.
- Apple contact identifiers are local implementation details, not cross-system IDs.
- Query fields are normalized according to their data type; combined queries use AND semantics and accept at most three distinct fields.
- Ambiguous matches must be reported; the CLI must not silently choose a record for a write.

## Safety and privacy

- Check Contacts authorization before reading or writing.
- Writes require explicit `--dry-run` or `--apply`.
- Never access the private Contacts database or upload contact data.
- Version 0.1 permits only the iCloud container; if it is unavailable, writes must fail rather than fall back to local or another account.

## Compatibility

The current deployment target is macOS 26.0+. Use the repository's Swift/Xcode toolchain and keep framework availability checks close to the adapter boundary.

## Metadata (0.1)

`metadata` belongs to the JSON contract only. Contacts 0.1 does not promise to write it into Apple Contacts; it must not be silently encoded into Notes, URLs, or another field. Any future persistence requires a versioned encoding and migration rule.
