# Phonetic contact names

## Current status

`macos-data-cli` now models and maps:

- `phoneticGivenName`
- `phoneticFamilyName`

They are present in `ContactPayload`, `ContactPatch`, `ContactsMapper`, and the
Contacts fetch/write key sets. Unit tests cover JSON round-trip and mapper
read/write behavior. A real apply and read-back test has now succeeded on the
fixed local test contact `xvk-test-contacts-001` with `あきら / かみじま`. This
validates the adapter path; it does not prove that every Contacts GUI view
displays the values in the same way.

## Implementation TODO

1. Verify stored values separately from Contacts GUI name order. Name order is a
   display preference and does not prove that phonetic values were persisted.
