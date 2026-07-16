# Usage

`macos-data` is a local Terminal CLI. It reads and writes macOS data through Apple public frameworks; agents do not need a special integration.

## Contacts

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

Check authorization and count records:

```text
macos-data contacts permission
macos-data contacts count
```

Read records as JSON:

```text
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
```

Search with one or more conditions. Conditions use AND semantics; at most three distinct fields are allowed:

```text
macos-data contacts query --name "Ada"
macos-data contacts query --phone "+1 555"
macos-data contacts query --email "ada@example.com"
macos-data contacts query --url "example.com"
macos-data contacts query --organization "Example"
macos-data contacts query --postal-code "10001"
```

Create from JSON. Always inspect a dry run before applying:

```text
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
```

The first Contacts version distinguishes `person` and `organization`. `external_id` is stored in a reserved URL using the form `x-macos-data://external-id/<id>`. The current writer uses the macOS default Contacts container; explicit container selection is planned.

During a regular edit, `external_id` is immutable. If the input contains an `externalID`, it must equal the ID in `--external-id`; changing an external ID requires a separate migration feature.

Set a contact image through a separate argument instead of embedding image data in the regular contact JSON:

```text
macos-data contacts edit --external-id <id> --image ./avatar.png --dry-run
macos-data contacts edit --external-id <id> --image ./avatar.png --apply
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
