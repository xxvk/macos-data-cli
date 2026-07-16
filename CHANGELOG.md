# Changelog

## 0.1.2 — 2026-07-16

Patch release aligning the CLI version with the published binary and Homebrew Cask.

## 0.1.0 — 2026-07-16

First Contacts adapter release.

### Added

- Contacts permission checking and iCloud container verification
- Contact count, list, get, and multi-condition query
- Person and organization contact types
- Create, partial edit, avatar update, delete, and external ID migration
- Reserved `macos-data-cli` URL label and `x-macos-data://external-id/<id>` format
- Avatar normalization: 10 MB input, 1024 px maximum dimension, 200 KB output
- JSON snapshot export
- Structured JSON success and error responses
- TDD unit tests and documented local end-to-end fixtures

### Current limitations

- macOS 26.0+ only
- Writes require an available iCloud Contacts container
- `metadata` is preserved in JSON but is not written into Apple Contacts
- vCard import/export is not implemented
- Batch operations and sync workflows are not implemented
