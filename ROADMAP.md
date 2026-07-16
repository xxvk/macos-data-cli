# macos-data-cli Roadmap

The project is currently in the design and prototype stage. No formal CLI commands have been implemented yet; command examples in the README describe the planned interface.

The long-term goal is to provide a general macOS native data access layer for agents and scripts. Different agents should be able to use the same CLI and JSON contract without depending on Codex, Claude Code, or another specific platform.

## Confirmed 0.1 design decisions

- `external_id` is a generic JSON field; the Contacts adapter should prefer storing it in a URL field rather than depending on the Contacts Notes entitlement.
- Accounts or containers must be selectable explicitly; the first implementation prioritizes the container that can sync with iCloud Contacts.
- The JSON contract supports `metadata`, but 0.1 does not promise to persist arbitrary metadata in Contacts.
- Deletion requires an explicit confirmation phrase in addition to `--apply`.
- The minimum target is macOS 26+; macOS 27 beta may be used for development and compatibility testing, but is not the stable support baseline.

## 0.1: Contacts adapter

The first version targets macOS 26+. macOS 27 beta may be used for early development testing.

- [ ] Create the Swift Package and CLI entry point
- [ ] Define stable JSON input, output, error, and exit-code formats
- [ ] Support `--help` and `--version`
- [ ] Read JSON from stdin or a file
- [x] Check and explain Contacts authorization
- [ ] Provide dry-run by default and require explicit apply for writes
- [x] List personal and organization contacts as JSON
- [x] Distinguish `person` and `organization` through `kind`
- [x] Support names, organizations, roles, email addresses, phone numbers, URLs, and postal addresses
- [x] Get a single contact by `external_id`
- [x] Query contacts by name, phone, email, URL, organization, and postal code
- [x] Support AND queries with up to three conditions
- [x] Add the basic contact create dry-run and apply flow
- [x] Reject duplicate `external_id` values before creation
- [ ] Support optional `external_id` and multi-factor matching
- [ ] Refuse automatic writes when a match is ambiguous
- [ ] Create, update, and delete contacts
- [ ] Return before/after changes and the final saved state
- [ ] Keep repeated operations as idempotent as practical

## Version roadmap

Each release is centered on one macOS data-domain adapter. Reliability, agent invocation, testing, installation, and release work are cross-cutting requirements for every iteration rather than separate releases.

### 0.2: Calendar adapter

- [ ] Use EventKit to access calendars and events
- [ ] Support calendars, events, times, locations, attendees, and notes
- [ ] Support event query, creation, update, and deletion
- [ ] Represent time zones and recurring events explicitly
- [ ] Include dry-run, the JSON contract, and authorization checks

### 0.3: Reminders adapter

- [ ] Use EventKit to access reminders
- [ ] Support reminder lists, titles, notes, due dates, and completion state
- [ ] Support reminder query, creation, update, and completion
- [ ] Support list selection and multi-factor matching
- [ ] Include dry-run, the JSON contract, and authorization checks

### 0.4: Notes adapter

- [ ] Evaluate the supported scope of Apple public Notes APIs
- [ ] Support note query and read operations
- [ ] Define the MVP boundary for folders, attachments, links, and rich text
- [ ] Document API limitations rather than relying on private database formats
- [ ] Add authorization checks, stable errors, and tests

### 0.5: Mail adapter

- [ ] Evaluate the supported scope of public Mail-related frameworks
- [ ] Define permissions for reading, searching, drafting, and sending mail
- [ ] Prioritize read-only queries and structured JSON output
- [ ] Require stronger confirmation for sending and deleting mail
- [ ] Avoid Mail's internal database and GUI automation

### 0.6: Photos adapter

- [ ] Evaluate the Photos framework access and authorization model
- [ ] Support read-only queries for photos and albums
- [ ] Support metadata, creation dates, locations, and asset references
- [ ] Define safety boundaries for export, modification, and deletion
- [ ] Include authorization checks, the JSON contract, and tests

## Cross-cutting requirements for every release

- [ ] Document Terminal, stdin, and stdout usage
- [ ] Update the shared agent invocation JSON contract
- [ ] Define consistent exit codes, errors, and authorization failures
- [x] Return structured JSON for the implemented read operations
- [ ] Provide dry-run, diffs, and explicit apply for writes
- [ ] Keep repeated operations as idempotent as practical
- [ ] Add unit tests, fixtures, and required integration tests
- [ ] Test on macOS 26+
- [ ] Update CLI help, README, and adapter documentation
- [ ] Provide reproducible source builds
- [ ] Update binaries and Homebrew installation when ready for release

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

Unit tests should prefer mocks and fixtures instead of relying on real Contacts, Calendar, or other personal data. Real system access belongs in explicit CLI smoke tests.

### Local Contacts integration-test fixture

See the detailed creation and recovery procedure: [Local Contacts Fixture](docs/development/local-contacts-fixture.md).

A person fixture and an organization fixture have been created once on the local Mac. Future tests must reuse them rather than creating more contacts:

```text
Name: macos-data Test Contact
Person external_id: xvk-test-contacts-001
Organization external_id: xvk-test-organizations-001
Create smoke-test external_id: org-create-apply-001
URL format: x-macos-data://external-id/<id>

The local Mac currently exposes one Contacts container named `iCloud`. The create smoke test wrote through the default container and verified the record by reading it back through the CLI. Explicit `--container` selection remains a future enhancement.
```

Standard verification command:

```bash
macos-data contacts get --external-id xvk-test-contacts-001 --format json
macos-data contacts get --external-id xvk-test-organizations-001 --format json
macos-data contacts get --external-id org-create-apply-001 --format json
```

Computer Use is allowed only for the initial creation or manual recovery of these fixtures. Normal development, testing, Release builds, and CLI smoke tests must not create more contacts. If a fixture is deleted, its URL is changed, or its type is changed, restore it before continuing.

## Long-term direction

- [ ] Evaluate additional Apple public frameworks
- [ ] Define a common adapter lifecycle and capability declaration
- [ ] Add cross-adapter batch operations and change detection
- [ ] Version the shared JSON contract

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
- Direct access to internal macOS databases
- Cloud uploads or centralized contact synchronization
- A built-in AI agent
- Coupling to one agent platform
- Making Obsidian a required part of the public data contract
