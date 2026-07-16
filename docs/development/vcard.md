# vCard Future TODO

## Current standard status

The current vCard specification is vCard 4.0, defined by [RFC 6350](https://www.rfc-editor.org/info/rfc6350/), published in 2011. It remains the base standard; later RFCs update or extend it, including parameter encoding and JSContact conversion. No published vCard 5.0 specification or confirmed release schedule is currently identified. Do not block implementation on a hypothetical vCard 5.0.

## Role in macos-data-cli

vCard should be implemented as a lossy exchange format, not as the authoritative Agent contract. JSON remains authoritative because it can preserve `external_id`, `kind`, metadata, image policy, and macOS-specific behavior explicitly.

## Planned mappings

| macos-data-cli | vCard 4.0 | Compatibility note |
|---|---|---|
| `givenName`, `familyName` | `N` | Standard |
| display name | `FN` | Required by vCard |
| `organizationName` | `ORG` | Standard |
| `jobTitle` | `TITLE` | Standard |
| email | `EMAIL` | Standard |
| phone | `TEL` | Standard |
| URL | `URL` | Standard |
| postal address | `ADR` | Structured escaping required |
| avatar | `PHOTO` | Client support varies |
| person / organization | `KIND:individual` / `KIND:org` | Not reliably preserved by every client |

## External ID strategy

Possible export representation:

```text
UID:xvk-test-contacts-001
X-MACOS-DATA-EXTERNAL-ID:xvk-test-contacts-001
```

`UID` is the closest standard property, but applications may treat it as their own record identity. The `X-` property is explicit but may be discarded by other applications. Import must detect both, prefer the project extension when present, and report when the ID was lost.

The reserved Contacts URL remains the authoritative macOS storage mechanism:

```text
x-macos-data://external-id/<id>
```

## Avatar strategy

vCard 4.0 supports `PHOTO`, including embedded image data or a URI. Export should embed the already-normalized image produced by the CLI, subject to the current 200 KB limit. Import must accept supported embedded PNG/JPEG data, enforce the 10 MB input limit, normalize to 1024 px and 200 KB, and reject unsupported or uncompressible images.

## TODO

- Add a vCard 4.0 writer for one contact and a collection.
- Add a parser with line unfolding, escaping, and UTF-8 handling.
- Preserve ordinary URLs separately from the reserved external-ID URL.
- Export `UID` and `X-MACOS-DATA-EXTERNAL-ID` with documented lossiness.
- Define import conflict behavior when IDs are missing, duplicated, or changed.
- Test `KIND:individual` and `KIND:org` against Apple Contacts and at least one other client.
- Test embedded PNG/JPEG `PHOTO` round trips and size normalization.
- Keep vCard conversion out of the Contacts JSON contract.

