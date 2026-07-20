# Usage

`macos-data` is a local Terminal CLI. It reads and writes macOS data through Apple public frameworks; agents do not need a special integration.

## Contacts

List available Contacts containers:

```text
macos-data contacts containers --format json
```

The default selector is the verified iCloud container. A command may select it
explicitly with `--container iCloud`, or use the exact iCloud container identifier from
the list:

```text
macos-data contacts list --container iCloud --format json
macos-data contacts get --external-id <id> --container <icloud-container-id> --format json
```

An unknown or non-iCloud container is an error; the CLI never silently falls
back to a local or Exchange account.

The current version writes only to the iCloud Contacts container:

```text
macos-data contacts container
```

If no iCloud container is available, all writes are rejected rather than falling back to a local or other account.

Export a JSON snapshot:

```text
macos-data contacts export --format json
macos-data contacts export --format json --output contacts-snapshot.json
```

`list` is for live reads; `export` is for a saved snapshot used for audit or batch agent processing.

Failures requested with `--format json` use the structured form:

```json
{"ok":false,"error":{"code":"CONTACT_QUERY_ERROR","message":"..."}}
```

Successful write operations requested with `--format json` return the saved
contact under `data.contact` together with an operation name. Delete returns
the contact state immediately before deletion:

```json
{"ok":true,"data":{"operation":"updated","contact":{}}}
```

External ID migration returns the migrated contact under `data.contact` with
the `from` and `to` identifiers.

Check authorization and count records:

```text
macos-data contacts permission
macos-data contacts count
macos-data contacts count --format json
```

JSON responses use contract version `0.1`, independent of the CLI release
version. Successful envelopes contain `ok`, `contractVersion`, and `data`;
errors contain `ok`, `contractVersion`, and `error`.

Read records as JSON:

```text
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
```

Search with one or more conditions. Conditions use AND semantics; at most three distinct fields are allowed:

```text
macos-data contacts query --name "Ada"
macos-data contacts query --kind organization
macos-data contacts query --phone "+1 555"
macos-data contacts query --email "ada@example.com"
macos-data contacts query --url "example.com"
macos-data contacts query --organization "Example"
macos-data contacts query --postal-code "10001"
```

Create from JSON. Always inspect a dry run before applying:

Every contact created through the CLI must include `externalID` in the JSON.
Contacts that originated outside the CLI may still be read without an external
ID, but the CLI will not create or manage a new record without one.

```text
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
cat contact.json | macos-data contacts create --stdin --dry-run
cat contact.json | macos-data contacts create --stdin --apply --idempotent
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
cat patch.json | macos-data contacts edit --external-id <id> --stdin --dry-run
```

The first Contacts version distinguishes `person` and `organization`. `external_id` is stored only in a URL labeled `macos-data-cli`, using the form `x-macos-data://external-id/<id>`. Other URL labels are ordinary URLs. The CLI selects the verified iCloud container by default; `--container iCloud` or the exact identifier can be used explicitly.

Retries are strict by default. Add `--idempotent` to a create retry only when
an existing contact with the same external ID should be accepted if all
persisted fields are equivalent. JSON-only metadata and avatar availability are
ignored for this comparison; a different persisted payload returns a conflict.
Add `--ignore-not-found` to a confirmed delete when an already-deleted record
should be treated as success.

Read responses include `imageAvailable`. This is the Contacts.framework
availability result and must not be interpreted as a definitive statement
about whether Contacts.app displays an iCloud avatar. Avatar apply responses
also include `avatar.status`; `readback_confirmed` is strong confirmation,
while `verification_unknown` means the save was accepted but the framework
could not safely read the avatar back. In that case follow `avatar.nextAction`
and do not automatically retry, delete, or recreate the contact.

During a regular edit, `external_id` is immutable. If the input contains an `externalID`, it must equal the ID in `--external-id`; changing an external ID requires a separate migration feature.

If a write reports CoreData error `134092`, macOS may have a corrupted or unsavable Contacts record. Preserve the JSON representation, then explicitly delete and recreate the contact before retrying. `macos-data` never performs that destructive recovery automatically.

Set a contact image through a separate argument instead of embedding image data in the regular contact JSON:

```text
macos-data contacts edit --external-id <id> --image ./avatar.png --dry-run
macos-data contacts edit --external-id <id> --image ./avatar.png --apply
```

To verify an existing avatar without writing anything:

```text
macos-data contacts avatar verify --external-id <id> --format json
```

The result is `readback_confirmed`, `not_available`, or
`verification_unknown`. A false lightweight preflight is reported as
`verification_unknown` rather than forcing a risky `imageData` read.

When an existing iCloud record cannot safely be edited in place, use the
separate replacement flow. It preserves the JSON contact fields but creates a
new Contacts record, so it requires an explicit confirmation:

```text
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --dry-run
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --apply --confirm "RECREATE CONTACT"
```

Images are limited to 10 MB on input. The processed image is kept within 1024 px on its longest side and 200 KB. Invalid, oversized, or uncompressible images are rejected before the contact is modified.

Regular edits are partial updates: omitted fields are preserved, while an explicit `null` clears that field.

### Metadata policy (0.1)

`metadata` is part of the JSON contract. Version 0.1 preserves it in JSON reads, edit previews, and exports, but does not write it into Apple Contacts. This avoids encoding project-private structure into Notes or another contact field.

Delete one contact by external ID. Preview first:

```text
macos-data contacts delete --external-id <id> --dry-run
```

Apply only with the exact confirmation phrase:

```text
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
```

Use a separate migration command to change an external ID:

```text
macos-data contacts external-id migrate --from <old-id> --to <new-id> --dry-run
macos-data contacts external-id migrate --from <old-id> --to <new-id> --apply --confirm "CHANGE EXTERNAL ID"
```

For the complete payload shape, error behavior, and safety rules, see [development rules](development/rules.md). For local verification records, see [local Contacts fixture](development/local-contacts-fixture.md).
