# macos-data-cli Roadmap

The project is currently at the Contacts adapter release baseline `0.1.7`.
The CLI and its core Contacts workflows are implemented locally; this roadmap
now distinguishes completed 0.1 behavior from remaining hardening work.

The long-term goal is to provide a general macOS native data access layer for agents and scripts. Different agents should be able to use the same CLI and JSON contract without depending on Codex, Claude Code, or another specific platform.

## Confirmed 0.1 design decisions

- `external_id` is a generic JSON field; the Contacts adapter should prefer storing it in a URL field rather than depending on the Contacts Notes entitlement.
- The first implementation targets the iCloud-capable Contacts container. The
  current CLI verifies and uses that container, with explicit iCloud selection
  available through `--container iCloud` or its exact identifier.
- The JSON contract supports `metadata`, but 0.1 does not promise to persist arbitrary metadata in Contacts.
- Deletion requires an explicit confirmation phrase in addition to `--apply`.
- The minimum target is macOS 26+; macOS 27 beta may be used for development and compatibility testing, but is not the stable support baseline.

## 0.1: Contacts adapter

The first version targets macOS 26+. macOS 27 beta may be used for early development testing.

- [x] Create the Swift Package and CLI entry point
- [x] Define the JSON success/error contract for implemented commands
- [x] Support `--help`, `--version`, and `-v`
- [x] Read JSON from stdin with `--stdin` (file input remains supported)
- [x] Check and explain Contacts authorization
- [x] Redact contact-sensitive values from diagnostics logs
- [x] Provide dry-run and require explicit apply for writes
- [x] List personal and organization contacts as JSON
- [x] Distinguish `person` and `organization` through `kind`
- [x] Filter queries by `kind` with `--kind person|organization`
- [x] Support names, organizations, roles, email addresses, phone numbers, URLs, and postal addresses
- [x] Support `phoneticGivenName` and `phoneticFamilyName` in the JSON contract and Contacts adapter
- [x] Get a single contact by `external_id`
- [x] Query contacts by name, phone, email, URL, organization, and postal code
- [x] Support AND queries with up to three conditions
- [x] Add the basic contact create dry-run and apply flow
- [x] Reject duplicate `external_id` values before creation
- [x] Support partial edit, avatar update, deletion, and external ID migration
- [x] Export a JSON snapshot
- [x] Report whether a contact has an avatar without fetching image bytes
- [x] Return explicit avatar write verification status after image apply
- [x] Add read-only `contacts avatar verify` with tri-state results
- [x] Add an explicit confirmed avatar replacement path for unsafe iCloud records
- [x] Require `external_id` for every CLI-created contact and support multi-factor matching
- [x] Refuse automatic writes when a match is ambiguous
- [x] Keep query matching and unique-match resolution in the framework-free `Core` layer
- [x] Return the final saved state consistently after create, edit, avatar, and
  delete apply operations
- [x] Return and locally verify the final saved state for external ID migration apply
- [x] Provide opt-in idempotent create retries and delete retries
- [x] Support `contacts containers` and explicit `--container iCloud`/identifier selection

## Version roadmap

Each release is centered on one macOS data-domain adapter. Reliability, agent invocation, testing, installation, and release work are cross-cutting requirements for every iteration rather than separate releases.

### 0.2: Mail adapter

Architecture decision: [Mail adapter 0.2.0](docs/development/mail-adapter-architecture.md).

- [x] Implement a read-only `mail doctor` for Mail-store discovery, Full Disk
  Access, Automation, and schema capability checks
- [x] Keep macOS 26.0 as the release baseline; enable the first direct-store
  fast path only for a runtime-verified `V10` schema fingerprint
- [x] Discover the highest supported `~/Library/Mail/V*` dynamically
- [x] Query accounts, mailboxes, counts, and bounded message metadata from
  `Envelope Index` through a strictly read-only SQLite connection
- [x] Parse locally cached `.emlx` and `.partial.emlx` files for explicit
  raw/text reads and partial-cache reporting
- [x] Enumerate and cross-check SQLite/EMLX attachment counts before any future
  bounded attachment export; partial-only content remains explicitly unverified
- [x] Fall back to public Mail.app Apple Events for explicit text reads when
  content is not cached; keep raw export cache-only and byte-exact
- [ ] Extend bounded fallback to unsupported account storage without weakening
  the fail-closed V10 metadata/schema gate
- [x] Add a non-mutating `mail reveal` command for visual verification in Mail.app
- [x] Return backend provenance, cache state, truncation/cursor information, and
  structured permission/schema errors
- [x] Use opaque local message IDs, keep selection/content/rendering parameters
  separate, and route raw RFC 822 bytes only through explicit `--output`
- [x] Enforce query deadlines, result caps, Apple Event circuit breaking, and
  prohibit recursive filesystem scans as automatic fallback
- [x] Never write Mail's SQLite database, WAL/SHM sidecars, `.emlx` files, or
  account configuration

### 0.3: Calendar adapter

- [ ] Use EventKit to access calendars and events
- [ ] Support calendars, events, times, locations, attendees, and notes
- [ ] Support event query, creation, update, and deletion
- [ ] Represent time zones and recurring events explicitly
- [ ] Include dry-run, the JSON contract, and authorization checks

### 0.4: Reminders adapter

- [ ] Use EventKit to access reminders
- [ ] Support reminder lists, titles, notes, due dates, and completion state
- [ ] Support reminder query, creation, update, and completion
- [ ] Support list selection and multi-factor matching
- [ ] Include dry-run, the JSON contract, and authorization checks

### 0.5: Notes adapter

- [ ] Evaluate the supported scope of Apple public Notes APIs
- [ ] Support note query and read operations
- [ ] Define the MVP boundary for folders, attachments, links, and rich text
- [ ] Document API limitations rather than relying on private database formats
- [ ] Add authorization checks, stable errors, and tests

### 0.6: Photos adapter

- [ ] Evaluate the Photos framework access and authorization model
- [ ] Support read-only queries for photos and albums
- [ ] Support metadata, creation dates, locations, and asset references
- [ ] Define safety boundaries for export, modification, and deletion
- [ ] Include authorization checks, the JSON contract, and tests

## Cross-cutting requirements for every release

- [x] Document Terminal, stdin, and stdout usage
- [x] Update the shared agent invocation JSON contract
- [x] Define consistent errors and authorization failures for implemented paths
- [x] Return structured JSON for the implemented read operations
- [x] Provide dry-run and explicit apply for implemented writes
- [x] Keep repeated operations idempotent when explicitly requested
- [x] Add unit tests and reusable local fixtures
- [x] Add a local CLI integration smoke test for reads and dry-runs
- [x] Run the optional disposable-contact CRUD path locally; temporary contact
  was created, edited, given an avatar, deleted, and verified absent
- [x] Test on macOS 26+ (verified on macOS 26.4 with Xcode 26.6 / SDK 26.5;
  earlier development also ran on macOS 27.0)
- [x] Update CLI help, README, and adapter documentation
- [x] Provide reproducible source builds
- [ ] Update binaries and Homebrew installation when ready for release

## Pre-release hardening TODO

- [x] Add process-level CLI tests for malformed JSON, empty stdin, missing flags,
  duplicate external ID conflicts, and container argument combinations
  (`scripts/run_cli_contract_tests.sh`)
- [x] Run one explicitly authorized local write integration pass covering create,
  edit, avatar, external ID migration, delete, and cleanup
  (`scripts/run_local_contacts_integration.sh --with-writes`)
- [ ] Verify the installed/Homebrew binary version separately from the source
  Release build
- [x] Verify phonetic fields with one explicitly authorized Japanese contact
  apply and read-back test (`xvk-test-contacts-001`)

## Standard development workflow: TDD to local release

Every new feature should follow this sequence. A feature is not complete merely because the code compiles:

1. **Define behavior**: specify the CLI command, input, output, exit codes, authorization requirements, and failure behavior.
2. **Write tests first**: add the expected behavior in the matching test directory. The first run should fail, proving the test covers the missing behavior.
3. **Implement minimally**: write only enough code to pass the tests while keeping Core, adapter, and CLI responsibilities separate.
4. **Run automated tests**: run `swift test`; all tests must pass.
5. **Verify the CLI**: run `swift run macos-data ...` for help, error, and success paths.
6. **Build Release**: run `swift build -c release` and verify the production configuration.
7. **Install locally**: install the release binary to the local Homebrew prefix, such as `/opt/homebrew/bin/macos-data`.
8. **Smoke-test the installed binary**: run the command through PATH and verify version, help, and the new feature.
9. **Update documentation**: update the README, roadmap, command examples, and authorization notes as needed.
10. **Delivery check**: run `git diff --check` and record test results, install path, and the scope of workspace changes.

Features involving system authorization must include:

- authorized-path tests;
- denied or unavailable-path tests;
- a real local authorization check; and
- a clear user-facing recovery message.

Unit tests should prefer mocks and synthetic fixtures instead of relying on real
Contacts, Mail, Calendar, or other personal data. Real system access belongs in
explicit CLI smoke tests. Mail fixtures must never contain data copied from a
real user's `Envelope Index` or `.emlx` cache.

### Local Contacts integration-test fixture

See the detailed creation and recovery procedure: [Local Contacts Fixture](docs/development/local-contacts-fixture.md).

A person fixture and an organization fixture have been created once on the local Mac. Future tests must reuse them rather than creating more contacts:

```text
Name: macos-data Test Contact
Person external_id: xvk-test-contacts-001
Organization external_id: xvk-test-organizations-001
Create smoke-test external_id: org-create-apply-001
URL format: x-macos-data://external-id/<id>

The local Mac currently exposes one Contacts container named `iCloud`. The create smoke test wrote through the default container and verified the record by reading it back through the CLI. Explicit `--container` selection is also verified locally against this container.
```

Standard verification command:

```bash
macos-data contacts get --external-id xvk-test-contacts-001 --format json
macos-data contacts get --external-id xvk-test-organizations-001 --format json
macos-data contacts get --external-id org-create-apply-001 --format json
```

Local CLI integration smoke test:

```bash
bash scripts/run_local_contacts_integration.sh
```

The default path is read-only plus dry-run. The optional full CRUD path creates
the disposable fixture from `Tests/Fixtures/integration-contact.json`, edits
it, writes an avatar, deletes it, and verifies that it is gone:

```bash
bash scripts/run_local_contacts_integration.sh --with-writes
```

This script is intentionally manual and local; it is not a CI job and is not
invoked by `swift test`. It must never delete the three permanent fixtures.

Computer Use is allowed only for the initial creation or manual recovery of these fixtures. Normal development, testing, Release builds, and CLI smoke tests must not create more contacts. If a fixture is deleted, its URL is changed, or its type is changed, restore it before continuing.

## Long-term direction

- [ ] Evaluate additional Apple public frameworks and document when a public
  framework does not expose the data needed by an adapter
- [ ] Define a common adapter lifecycle and capability declaration
- [ ] Add cross-adapter batch operations and change detection
- [x] Version the shared JSON contract independently from the CLI release

Each adapter should define its own authorization requirements, model mapping, read/write capabilities, errors, and tests.

## Remaining design details

- Define the canonical URL format and reserved scheme for `external_id`
- Define how the iCloud-capable container is identified and how missing containers are reported
- Define warning output when `metadata` cannot be mapped to Contacts
- Decide whether the deletion confirmation phrase should include the contact name or external ID
- Define the macOS 26/macOS 27 API and authorization regression matrix

## Out of scope for now

- GUI automation and screen-coordinate workflows
- Apple private APIs
- Writes to internal macOS databases; the Mail adapter permits only its
  documented, replaceable, strictly read-only local-index path
- Cloud uploads or centralized contact synchronization
- A built-in AI agent
- Coupling to one agent platform
- Making Obsidian a required part of the public data contract
