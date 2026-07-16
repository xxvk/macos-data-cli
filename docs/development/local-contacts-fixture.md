# Local Contacts Fixture

## Purpose

This document describes the two one-time local Contacts records used for real integration and CLI smoke tests.

Unit tests must use mocks or fixtures. These contacts exist only to validate the real macOS Contacts access path.

## Fixed test records

The fixture set contains two classification fixtures and one create smoke-test fixture.

### Person

```text
Name: macos-data Test Contact
Organization: macos-data Test
Phone: +1 555 010 0001
Email: macos-data-test@example.invalid
URL: x-macos-data://external-id/xvk-test-contacts-001
external_id: xvk-test-contacts-001
```

Expected `kind`: `person`

### Organization

```text
Name: macos-data Test Organization
Phone: +1 555 010 0002
Email: organization-test@example.invalid
URL: x-macos-data://external-id/xvk-test-organizations-001
external_id: xvk-test-organizations-001
```

This record must be created as a company/organization contact, not as a person with an organization name.

Expected `kind`: `organization`

### Create smoke-test record

```text
Name: Apply Test Organization
Email: apply-test@example.invalid
URL: x-macos-data://external-id/org-create-apply-001
external_id: org-create-apply-001
```

Expected `kind`: `organization`

The `.invalid` email domain is intentional and must not be replaced with a real address.

## One-time creation

Use the Contacts app to create the records and add the fields above. The URL is the important field because the CLI extracts the external ID from it.

Do not create another copy if the record already exists.

## Container verification

The local Contacts store currently exposes one container named `iCloud`. The create smoke test was written through the default container and verified by reading the record back through the CLI. All three fixture records use the reserved URL label `macos-data-cli`.

Explicit `--container` selection remains a future enhancement for Macs with multiple accounts or containers.

## Avatar fixtures

The three image fixtures in this directory are assigned as follows:

| Contact | Image |
|---|---|
| `xvk-test-contacts-001` | `icon1.png` |
| `xvk-test-organizations-001` | `icon2.png` |
| `org-create-apply-001` | `icon3.jpeg` |

They were written with the installed CLI using `contacts edit --image ... --apply` and are intended for repeatable local verification.

## CLI verification

Run the installed CLI:

```bash
macos-data contacts permission
macos-data contacts count
macos-data contacts get --external-id xvk-test-contacts-001 --format json
macos-data contacts get --external-id xvk-test-organizations-001 --format json
macos-data contacts get --external-id org-create-apply-001 --format json
```

The commands must return one JSON object each, with `kind` values of `person` and `organization` respectively.

## CRUD smoke-test sequence

Use the existing fixtures for read-only verification. A disposable contact should be used before running a destructive end-to-end sequence:

```text
create --dry-run -> create --apply -> get -> edit --dry-run -> edit --apply -> image --dry-run -> delete --dry-run -> delete --apply -> get (not found)
```

Do not run the final `delete --apply` against the three permanent fixtures documented above.

## Recovery

Computer Use is needed only if a fixture is deleted or its identifying URL/type is changed. Restore the fixed fields and type above, then rerun the CLI verification commands.

Normal unit tests, builds, release packaging, and CLI smoke tests must not create or delete Contacts records.

The temporary integration fixture is defined in `Tests/Fixtures/integration-contact.json`. It may be created for a complete end-to-end run, but must be deleted at the end and must never become a permanent fixture.
