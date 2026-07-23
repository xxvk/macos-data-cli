# Usage

`macos-data` is a local Terminal CLI. It reads and writes macOS data through Apple public frameworks; agents do not need a special integration.

## Mail (0.2)

Run the read-only capability check:

```text
macos-data mail doctor --format json
```

`doctor` dynamically discovers the highest numeric `~/Library/Mail/V*`, opens
`Envelope Index` read-only, and checks WAL, database consistency, required
schema, Full Disk Access, and current Automation state. It does not launch
Mail.app, prompt for permission, or read subjects, addresses, mailbox names, or
message bodies.

`fastPathAvailable: true` means the current host passes the V10 SQLite metadata
fast-path gate. It is not a promise about future Mail schemas; every run probes
again. `target_not_running` or `requires_consent` Automation status does not
disable SQLite, but means text fallback or `mail reveal` is not currently available.

Discover privacy-safe account scopes and mailboxes:

```text
macos-data mail accounts --format json
macos-data mail mailboxes --format json
macos-data mail mailboxes --account-id <opaque-account-id> --format json
```

Account IDs are derived opaque local scopes; raw account authorities and full
mailbox URLs are not returned. Mailbox and message IDs are also opaque and must
be treated as adapter-owned values.

When the V10 schema/FDA fast path is unavailable, the CLI may use Mail.app only
if Mail is already running and Automation is authorized. This metadata fallback
has a five-second Apple Event timeout and hard caps of 32 accounts, 200 top-level
mailboxes, and 25 message candidates. Its query result is always `incomplete`,
has no cursor, and reports `backend: "mail_app"` plus the fallback reason.
Fallback `ambx_`/`appmsg_` IDs are local adapter values and are not interchangeable
with SQLite IDs. Raw export and attachment verification remain fast-path-only.

Query bounded message metadata:

```text
macos-data mail query --unread --limit 50 --format json
macos-data mail query --mailbox-id <id> --subject <text> --format json
macos-data mail query --from <text> --received-after 2026-07-01 --format json
macos-data mail query --cursor <cursor> --limit 50 --format json
```

Filters use AND semantics. Supported filters are `--account-id`, `--mailbox-id`,
`--from`, `--to`, `--subject`, `--received-after`, `--received-before`,
`--unread`, `--flagged`, and `--has-attachment`. Dates use ISO 8601. The default
limit is 50 and the maximum is 200. A truncated result includes `nextCursor`.
Queries use bound parameters and a 250 ms SQLite deadline; they read envelope
metadata only, not message bodies.

On the Mail.app metadata fallback, filters are applied only to the bounded
candidate set, nested mailboxes are not enumerated, and `--cursor` is rejected.
Callers must preserve the returned limitations rather than treating a no-match
result as a complete mailbox search.

Mail results report `backend`; query results additionally report `cacheState`,
`truncated`, `nextCursor`, `elapsedMs`, `fallbackReason`, `incomplete`, and
`limitations`. Metadata stays on `backend: "sqlite"`; explicit text reads may
report `sqlite_emlx` or `mail_app` according to the observed source.

Read one message by the opaque ID returned from `mail query`:

```text
macos-data mail get --id <id> --format json
macos-data mail get --id <id> --content text --format json
macos-data mail get --id <id> --content raw --output message.eml --format json
macos-data mail get --id <id> --content raw --output -
```

The default projection is `metadata` and does not read the EMLX payload.
`--content text` explicitly reads cached content, decodes common MIME transfer
encodings and charsets, prefers a non-attachment `text/plain` part, and otherwise
returns sanitized text from HTML. It does not use WebKit or load remote resources.

`--content raw` writes exact cached RFC 822 bytes and always requires `--output`.
Raw bytes are never embedded in JSON. `--output -` cannot be combined with
`--format json`; a named output file must not already exist. Reads are capped at
64 MiB with a 100 ms local-file budget; extracted text is capped at 2 MiB and
MIME nesting at eight levels.

`cacheState: "partial"` is never reported as complete. If cached text is absent,
an explicit text read may use serialized Mail.app Apple Events with a 3-second
timeout and 30-second circuit breaker. This fallback does not auto-launch Mail;
permission denial, Mail not running, and lookup failure remain observable. Raw
export never falls back because Mail.app's text `source` cannot guarantee exact
cached bytes. Opaque local IDs can become stale after Mail reindexes or moves a
message.

Reveal one result visibly in Mail.app:

```text
macos-data mail reveal --id <id> --format json
```

`reveal` may launch and activate Mail.app. It uses the same opaque local ID and
does not intentionally change read, flag, mailbox, or message data.

Cross-check attachment metadata without exporting attachments:

```text
macos-data mail attachments verify --id <id> --format json
```

The verifier returns only SQLite and MIME counts, cache state, and whether a
complete cached EMLX matched. It does not return names, paths, or payloads.
Partial or missing EMLX is always `incomplete` and never `matched`, even if the
currently visible counts happen to agree.

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
