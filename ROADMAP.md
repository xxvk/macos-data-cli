# macos-data-cli Roadmap

The Calendar adapter release `0.3.0` is published.
The Contacts, read-only Mail, and Calendar workflows are implemented and locally verified;
this roadmap distinguishes released behavior from later adapters and distribution work.

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
- [x] Extend bounded fallback to unsupported account storage without weakening
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

Architecture: [Calendar adapter 0.3](docs/development/calendar-adapter-architecture.md).

- [x] Complete the 0.3 naming decision: retain `macos-data` as the sole canonical
  command for 0.3.0 and the complete 0.x line, introduce no alias, and keep
  `xvk-data` rejected. Naming is reviewed again as a 1.0.0 release gate without
  pre-committing to a rename. See [`ADR 0001`](docs/development/adr/0001-cli-name-until-1.0.md)
  and the [`naming audit`](docs/development/naming-audit.md).
- [x] Use EventKit to access calendars and events; local full-access authorization
  and the privacy-safe read smoke pass
- [x] Support calendars, events, times, locations, attendees, and notes; attendees
  remain explicitly read-only in 0.3
- [x] Support event query, creation, update, and deletion
  - Query, get, create/edit/delete code paths and dry-runs are implemented
  - `calevent_` binds a calendar item and occurrence start for precise recurrence selection
  - The disposable-event create/read/edit/read/delete/absence gate passed against the local iCloud Calendar
  - Alarms, all-day date-only values, a privacy-minimized 60-second idempotency receipt, and conflict detection are implemented
  - A real six-occurrence gate covers immediate retry, alarms, this/future edits and deletes, and final cleanup
  - The real feature gate covers all-day read-back, relative/absolute/cleared alarms,
    non-equivalent idempotent retry rejection, strict overlap versus adjacent
    boundaries, and final zero-residue cleanup
  - Calendar hardening covers Tokyo, UTC, both DST boundaries, receipt expiry and
    permissions, idempotency mismatch, malformed contracts, and the 200-event cap
- [x] Represent IANA time zones and recurring events, including recurrence ends
  and ordinal weekdays, explicitly
- [x] Include dry-run, the JSON contract, full-access checks, stable errors, and Calendar exit 5
- [x] Align `VERSION`, CLI `--version`, both Info.plists, README, INSTALL, tests,
  and CHANGELOG at 0.3.0; the local Release and installed Homebrew-prefix binary
  both report 0.3.0
- [x] Pass the default no-apply 0.3.0 release gate: 121 Swift tests, shared and
  Calendar CLI contracts, Calendar read/dry-run smoke, Mail read-only smoke,
  Release build, signed Debug app verification, version audit, and diff check
- [x] Commit the final release candidate, merge it to `main`, rerun the gate from
  a clean `main` worktree, create annotated tag `v0.3.0`, publish the GitHub
  Release asset, update the Homebrew Cask, and verify the installed 0.3.0 CLI

### 0.4: Reminders adapter

Architecture draft: [Reminders adapter 0.4](docs/development/reminders-adapter-architecture.md).

- [x] Define and review the 0.4 Reminders architecture before implementation:
  user workflows, iCloud source/list selection, permissions, JSON models,
  stable identifiers, recurrence and alarm semantics, pagination, write safety,
  idempotency, error contract, and TDD/release gates
- [x] Use EventKit to access reminders
  - TDD foundation implemented: dedicated `RemindersAdapter` target, stable
    permission errors/exit 6, full-access request, unique iCloud source
    selection, and reminder-list discovery
  - Local privacy-minimized verification passed with full access, one selected
    source, and six lists; no reminder titles or contents were emitted
  - Read-only query/get now use EventKit fetch plus local/server opaque-ID lookup;
    fetches have a tested 10-second timeout and Task-cancellation path, a
    post-fetch 5,000-item response cap, and incomplete due ranges are pushed
    into EventKit predicates; EventKit still materializes its result array first
- [x] Support reminder lists, titles, notes, due dates, and completion state
  - Read JSON includes opaque ID, list, title, notes, URL, normalized priority,
    completion state/date, start/due DateComponents, alarm details (including
    read-only location alarms), and complete recurrence-rule details
  - Date mapping distinguishes date-only, floating timed, and IANA-zone timed values
- [x] Support reminder query, creation, update, and completion for non-recurring reminders
  - `reminders query` and `reminders get` are implemented with status, due range,
    list, title, limit, and opaque anchor cursor filters; cursors contain
    privacy-safe SHA-256 fingerprints of the query, selected lists, and last
    emitted item, avoiding silent offset drift
  - Partial update is implemented with fail-closed patch decoding, nullable-field
    clearing, writable iCloud list moves, location-alarm preservation, one save,
    and explicit read-back states; real edit apply passed with final zero residue
  - Complete/reopen are implemented with explicit completion timestamps, safe
    no-op repeats, one-save apply, read-back states, and separate recurring
    `nextOccurrence`; real apply and repeated no-op verification passed
  - `create --dry-run|--apply [--idempotent]` is implemented with fail-closed JSON decoding, normalized
    date/alarm/recurrence validation, writable-list resolution, and an ID-less
    draft, EventKit save, opaque ID, immediate read-back states, and a private
    60-second receipt
  - Single-item delete preview/apply requires `--confirm "DELETE REMINDER"`, removes
    exactly once, and distinguishes confirmed absence from pending read-back
  - The disposable create/get/edit/complete/reopen/delete gate includes trap cleanup and final zero-match
    verification; it passed against local iCloud with final matching count zero
- [x] Verify recurring-reminder completion behavior against real iCloud EventKit
  - Create one disposable daily recurrence, complete the current occurrence,
    verify the next incomplete occurrence without inventing hidden instances,
    then remove the entire disposable fixture with zero residue
  - The local iCloud gate passed: the due date advanced, EventKit reused the
    opaque reminder ID, `nextOccurrence` matched the query result, and cleanup
    confirmed zero matching reminders
- [x] Support list selection and multi-factor matching
  - Query combines status, due range, list, and title with AND semantics; list
    selection accepts an opaque ID or unique title and rejects ambiguity
- [x] Include dry-run, the JSON contract, and authorization checks
  - Authorization, JSON envelopes, exit 6, read contract tests, Release
    compilation, and a privacy-minimized local read smoke are implemented
  - Unified `resources` discovery reports the selected Reminders iCloud source
    as readable and writable now that guarded create apply is implemented

### 0.5: Photos adapter

- Architecture: [Photos adapter 0.5](docs/development/photos-adapter-architecture.md)
- [x] Evaluate the Photos framework access and authorization model
  - PhotoKit public APIs are viable. The first runtime slice is read-only
    metadata and never reads private databases or downloads media bytes
  - Full and limited access are distinct; limited results report
    `complete: false`, and add-only permission is insufficient for reads
  - Export is separate, no-network by default, and must distinguish available
    metadata from iCloud-backed original bytes
  - TDD permission/resource foundation is implemented with explicit limited
    scope, status-only versus request commands, Info.plist usage text, stable
    exit/error codes, and full regression plus no-write CLI contract passes
- [x] Support read-only queries for photos and albums
  - Album discovery is implemented with user folder hierarchy, user/smart
    kinds, duplicate-title preservation, opaque IDs, kind-bound anchor cursors,
    default 50/maximum 200 pages, and limited-access `complete: false`
  - Synthetic TDD and permission-before-fetch behavior pass. The privacy-safe
    real-library gate passed through the stable app identity with 34 aggregate
    collections (11 user, 23 smart, 0 folders), `complete: true`, no truncation,
    and no title/identifier/location/media output
  - Asset query/get now supports a maximum 366-day creation range, album/media/
    favorite filters, hidden and location opt-ins, opaque IDs, stable ordering,
    filter-bound pagination, and metadata-only PhotoKit fetches
- [x] Support metadata, creation dates, locations, and asset references
  - The payload includes media kind/subtypes, dimensions, duration, creation and
    modification dates, favorite/hidden/burst/Live Photo state, opaque asset ID,
    and opt-in coordinates. Byte availability remains explicitly `unknown`
- [x] Define safety boundaries for export, modification, and deletion
  - Export is one asset per command, no-network and no-overwrite by default,
    never emits media bytes to JSON/stdout, distinguishes resource variants,
    and uses private temporary output plus atomic move
  - The runtime command and TDD file coordinator are implemented. The offline
    live gate checked five iCloud-only candidates: all failed closed with
    `PHOTOS_CONTENT_NOT_LOCAL`, downloaded nothing, and left no output. On
    2026-08-14, an explicitly user-approved network gate exported one original
    from the same five-candidate sample, verified nonzero bytes and mode `0600`,
    and removed the private temporary output on exit
  - Import and metadata mutation remain deferred behind dry-run/apply and a
    disposable-fixture cleanup gate. Deletion is last and must preserve
    Recently Deleted semantics plus an exact confirmation phrase
- [x] Include authorization checks, pagination, the JSON contract, and tests
  - Nineteen Photos adapter tests, 176 total Swift tests, and CLI negative
    contracts pass. The live gate
    runs through a stable LaunchServices app identity and keeps asset JSON in a
    private temporary directory, printing aggregate counts only. The 30-day
    metadata sample returned the five-item cap and one opaque-ID get read-back passed

### 0.6: Notes adapter

- Feasibility decision: [Notes adapter 0.6](docs/development/notes-adapter-feasibility.md)
- [x] Audit the supported scope of Apple public Notes APIs before promising a
  release number or implementation
- [x] Decide whether a useful public-interface-only adapter can support note and
  folder query/read without private database access or GUI-coordinate automation
  - The macOS 26.5 SDK has no public Notes content framework. Notes.app 4.13 does
    publish a scripting dictionary, so the accepted boundary is a read-only,
    TCC-governed Apple Events adapter accurately labeled as Automation
- [x] Define the possible MVP boundary for attachments, links, and rich text
  - 0.6 includes attachment metadata and opt-in plaintext/HTML reads. Binary
    export is deferred; tags, pinned state, rich-content structure, and lossless
    HTML/Markdown round trips are not promised
- [x] Assign version 0.6 and require authorization checks, stable errors, JSON
  contracts, bounded Apple Events, synthetic TDD, and privacy-safe live gates
- [x] Explicitly prohibit private Notes databases, private frameworks, direct
  CloudKit-container access, and GUI-coordinate automation
- [x] Implement the permission and capability foundation
  - Added status-only and explicit-request commands, stable Automation states
    and errors, a read-only unified `notesLibrary` resource, Info.plist usage
    text, four synthetic tests, and CLI contract coverage. The non-prompting
    local probe correctly reported `requiresConsent`
- [x] Implement account and nested-folder discovery with opaque IDs
  - Discovery is bounded to 32 accounts, 200 folders, depth 16, and five
    seconds. SHA-256-derived IDs hide raw scripting identifiers; hierarchy,
    default account, shared state, scoped pagination, and completeness are
    covered by synthetic tests
  - The stable-app live gate passed with one account and 12 folders,
    `complete: true`, no truncation, aggregate-only output, and temporary JSON
    cleanup
- [x] Implement bounded metadata query and filter-bound pagination
  - Metadata-only query supports account, folder, title substring, and
    modification-time filters plus filter-bound opaque cursors. Enumeration is
    capped at 200 notes and recursively walks at most 16 folder levels under a
    five-second Apple Events deadline
  - 19 Notes adapter tests, 195 total Swift tests, and CLI negative contracts
    pass. The stable-app live
    gate returned 163 notes, `complete: true`, no truncation, and full
    creation/modification-date coverage while printing aggregate counts only
- [x] Implement one-note get with explicit plaintext/HTML body opt-in
  - Metadata-only is the default and does not call the body bridge. Plaintext or
    HTML requires an explicit projection, password-protected notes fail closed,
    and returned UTF-8 body content is capped at 256 KiB without diagnostic logging
  - Synthetic tests cover metadata-only behavior, projection isolation, escaped
    scripting IDs, locked notes, and oversized bodies. Disposable-note body
    read-back remains part of the final stable-app live gate
- [x] Add attachment metadata; defer binary export to its own safety gate
  - Explicit opt-in returns at most 100 opaque attachment metadata records and
    never reads attachment contents or invokes save/export. Synthetic mapping
    and script-boundary tests pass; the live zero-attachment path returned an
    empty complete list
- [x] Complete the stable-app Automation and disposable-note live gates
  - Query, metadata-only get, plaintext, HTML, and zero-attachment read paths
    passed through the stable app. The disposable note was permanently removed
    through Notes UI after explicit action-time approval; the final signed-app
    title query confirmed zero matches

### 0.6.1: Notes guarded writes

Version decision: 0.6.0 remains the bounded read-only Notes release. Notes
write support is developed and released separately as 0.6.1. All mandatory
implementation and local release gates passed before the version was changed.

- [x] Define fail-closed write contracts and stable write/read-back states
  - Every mutation defaults to `--dry-run`; persistence requires `--apply` and
    structured JSON. Return `readback_confirmed` or
    `save_accepted_readback_pending`, or `outcome_unknown`; Agents must not retry
    pending or unknown outcomes
- [x] Implement note creation in one explicitly selected folder
  - Accept input file/stdin, never body text as a CLI argument. Support
    plaintext converted to escaped HTML and explicit HTML, cap UTF-8 input at
    256 KiB, reject unknown fields, locked/shared targets, and ambiguous folder
    selection, and add a private short-lived idempotency receipt
- [x] Implement note rename with optimistic concurrency
  - Require one opaque note ID plus expected `modificationDate`; return a dry-run
    metadata diff without logging title/body content, save once, and read back
- [x] Implement note move with explicit destination and identity verification
  - Require one opaque destination folder, fail closed across ambiguous account
    scope, verify the moved note and whether its opaque ID changed, and never
    infer a destination from a folder title
- [x] Keep existing-note body replacement outside the initial 0.6.1 release gate
  - Whole-body HTML replacement can destroy unsupported rich structures and
    attachment references. It needs a separate expected-modification token,
    body hash preview, complex-content rejection, and disposable rich-note gate
- [x] Keep attachment mutation and note deletion outside the initial 0.6.1 gate
  - Attachment add/remove needs independent file-size, local-file, cleanup, and
    read-back rules. Delete remains soft-delete only and needs exact
    confirmation plus documented Recently Deleted visibility; permanent delete
    and empty-trash operations are not supported
- [x] Complete synthetic TDD, CLI negative contracts, and a disposable iCloud
  create/rename/move/read-back/cleanup integration gate with zero active residue
  - 28 Notes tests and 204 total Swift tests pass. CLI negative contracts cover
    missing input, strict unknown-field rejection, conflicting modes, missing
    IDs, and binding confirmation phrases
  - The stable signed app completed create, rename, move, and immediate read-back
    in two explicit non-shared iCloud folders. A generated-script newline bug and
    HTML-normalization false pending were found and fixed with compile-only and
    canonical-plaintext hash tests. Four explicitly audited test notes were
    permanently removed through Notes UI, the unrelated Recently Deleted note
    was preserved, and a signed-app title query confirmed zero fixture matches
- [x] Update `notesLibrary` writable capability, help, README, usage, CHANGELOG,
  and version metadata only after all mandatory 0.6.1 gates pass

### 0.6.2: Notes body and folder lifecycle

Version decision: development remained at 0.6.1 until all mandatory tests,
signed-app mutation gates, and cleanup checks passed. Source version metadata
was then updated together to 0.6.2.

Current forward-compatibility baseline: Xcode 27.0 Beta 5 (`27A5237l`), Swift
6.4, and macOS SDK 27.0 compile the Release/debug app and pass all 222 Swift
tests. Standard tests use `scripts/run_swift_tests.sh` to keep generated XCTest
bundles outside this iCloud/File Provider checkout.

- [x] Add guarded replacement of an existing note body
  - Introduce a dedicated `notes edit-body` command; do not overload `rename`
  - Accept strict JSON from file/stdin with `bodyFormat`, `body`,
    `expectedModificationDate`, and `expectedBodySHA256`
  - Preserve the 256 KiB input limit, default dry-run, explicit apply, private
    hashes/byte counts, serialized Apple Events, and immediate read-back states
  - Reject shared/password-protected notes and notes containing attachments or
    unsupported rich structures. The first release replaces only a body proven
    safe for the supported plaintext/HTML subset; it does not promise lossless
    editing of checklists, tables, drawings, scans, or collaboration content
  - Implementation, strict CLI parsing, generated-script compilation, dry-run
    no-write proof, hash/concurrency checks, attachment/rich-content rejection,
    timeout handling, and synthetic read-back tests are complete. All 32 Notes
    tests, 208 total Swift tests, CLI no-apply contracts, and the release build
    pass. The disposable signed-app gate completed create, body edit,
    hash-confirmed read-back, rename, and move across two explicit non-shared
    iCloud folders. After action-time confirmation, only the fixture was
    permanently removed through Notes UI; the unrelated Recently Deleted note
    was preserved and the final signed-app sentinel query returned zero matches
  - The first gate attempt safely stopped before mutation because the wrapper's
    eight-second output wait was shorter than Notes plus LaunchServices startup.
    Read-back proved the original body was unchanged. The wrapper now waits up
    first to 20 seconds and now to 40 seconds after Xcode 27 app startup/output
    exceeded 20 seconds; it reports the exact stage while the Apple Event
    deadline remains five seconds
- [x] Add explicit Notes folder create and rename operations; reassess move
  - Operate only in the locally bound iCloud account and select parents and
    destinations by opaque folder ID; never infer a folder from its display name
  - Require strict file/stdin JSON, default dry-run, explicit apply, read-back,
    and privacy-safe output. Create should support a short-lived idempotency
    receipt and reject ambiguous duplicate outcomes
  - Before implementation, verify the Notes 4.13 scripting behavior for nested
    create/rename/move, identity changes, shared folders, duplicate names, and
    moving a folder into itself or one of its descendants. Fail closed wherever
    the public dictionary cannot provide a stable precondition or read-back
  - Create/rename implementation, strict JSON parsing, privacy-safe output, name-hash/current-
    parent guards, default/shared/cross-account/duplicate/cycle rejection,
    idempotency receipts, timeout states, generated-script compilation, targeted
    Store tests, and CLI no-apply contracts are complete
  - The signed-app gate proved nested create, duplicate rejection, rename, hash
    read-back, and cleanup. Notes 4.13 folder move did not preserve a confirmable
    folder identity: the empty child disappeared from the enumerable graph and
    metadata was temporarily invalid. Apply is now disabled with
    `NOTES_FOLDER_MOVE_UNSUPPORTED`; a future move implementation requires a new
    design and separate gate rather than retrying the public AppleScript command
  - The live gate also exposed duplicate scripting IDs when account-level folder
    enumeration was recursively collected. Discovery now starts from true root
    folders and validates graph uniqueness, failing closed instead of crashing
  - After explicit cleanup authorization, all three disposable folders were
    permanently removed in Notes UI. A final signed-app query returned
    `complete=true`, zero matches for all three opaque IDs, and zero
    `macos-data-folder-gate-*` sentinel matches
- [x] Assess guarded empty-folder deletion and fail closed
  - Delete only an explicitly selected, non-shared, non-default empty folder in
    the bound account; reject recursive deletion and folders containing notes or
    child folders
  - Require `--apply`, the exact confirmation phrase
    `DELETE EMPTY NOTES FOLDER`, a fresh pre-delete emptiness check, and a final
    absence read-back. Permanent trash clearing is outside this command
  - Preview implementation and synthetic TDD cover strict parent/name-hash input,
    non-recursive child/note rejection, stable `NOTES_FOLDER_NOT_EMPTY`, CLI
    negative contracts, and privacy-safe output
  - The signed-app apply gate invalidated the metadata graph after deleting the
    renamed child. After restarting Notes, that child reappeared with its old
    name and a new opaque ID. A short-lived absence therefore cannot prove a
    durable iCloud deletion
  - Apply now returns `NOTES_FOLDER_DELETE_UNSUPPORTED` before any write Apple
    Event. Future enablement requires a different public mechanism and a new gate
  - After explicit action-time confirmation, the three disposable fixtures were
    removed leaf-first through Notes UI. A post-restart signed-app query returned
    `complete=true`, zero matches for all four known pre/post-resurrection opaque
    IDs, and zero `macos-data-folder-gate-*` sentinel matches
- [x] Add guarded single-note deletion
  - Implement recoverable soft deletion to Notes Recently Deleted only; do not
    expose permanent deletion or empty-trash operations
  - Require one opaque note ID, `expectedModificationDate`, `--apply`, and the
    exact confirmation phrase `DELETE NOTE`; reject shared/locked notes and
    verify that the note is absent from its former active folder
  - Return an explicit pending/unknown state when Recently Deleted visibility
    cannot be proven, with a `nextAction` that forbids automatic Agent retry
  - Implementation and synthetic TDD are complete: strict date-only mutation
    JSON, fresh direct read, shared/locked/stale rejection, exact `DELETE NOTE`
    confirmation, privacy-safe output, generated-script compilation, timeout
    unknown handling, and no-apply CLI contracts pass
  - The authorized signed-app gate completed create, body edit, rename, and move.
    Its wrapper stopped after 20 seconds during move output, so the command was
    not retried; a read-only get proved the move had succeeded. Continuing from
    that confirmed state, one dry-run and one delete apply returned
    `readback_confirmed`, zero matches in the former folder, and one recoverable
    match in another system-managed folder. After explicit action-time approval,
    only the fixture was permanently removed through Notes UI; one unrelated
    Recently Deleted note was preserved, and the final signed-app sentinel query
    returned `complete=true` with zero matches
- [x] Complete 0.6.2 TDD, signed-app integration, and cleanup gates
  - Final synthetic baseline: 222 Swift tests plus CLI no-apply contracts pass,
    covering strict JSON, concurrency/hash conflicts, rich-content rejection,
    folder-cycle prevention, non-empty delete rejection, confirmation phrases,
    timeout unknown outcomes, no-op behavior, and diagnostic redaction
  - Disposable simple/rich notes and an isolated nested folder tree verified body
    edit, folder create/rename, move and folder-delete fail-closed behavior, and note
    soft deletion. Action-time-confirmed UI cleanup preserved unrelated Recently
    Deleted data and final signed-app sentinel queries returned zero matches
  - The final local release gate passed version consistency, Release/signed-debug
    builds, CLI and Calendar contracts, Mail read-only smokes, and `git diff --check`.
    This host currently has two matching iCloud Calendar sources, so Calendar live
    smoke verified the stable ambiguity error and skipped rather than guessing
  - Help, README, usage, architecture notes, CHANGELOG, capability output, and all
    version entry points were updated together to 0.6.2 only after these gates passed

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
- [x] Build, publish, and install versioned Release binaries through the public
  Homebrew Cask (verified through 0.3.0)
- [ ] Replace ad-hoc distribution with Developer ID signing and Apple
  notarization; this remains a separate distribution goal

## Pre-release hardening TODO

- [x] Add process-level CLI tests for malformed JSON, empty stdin, missing flags,
  duplicate external ID conflicts, and container argument combinations
  (`scripts/run_cli_contract_tests.sh`)
- [x] Run one explicitly authorized local write integration pass covering create,
  edit, avatar, external ID migration, delete, and cleanup
  (`scripts/run_local_contacts_integration.sh --with-writes`)
- [x] Verify the locally installed binary separately from the source Release
  build (`scripts/run_installed_release_smoke.sh`: 0.2.0, V10 fast path,
  SQLite query backend)
- [x] Verify the public Homebrew Cask artifact URL, SHA-256, archive layout,
  managed binary link, `--version`, and installed smoke test for 0.3.0
- [ ] Repeat the public Cask test on an independent clean Mac; the current
  verification used a clean Cask installation state on the development Mac
- [x] Verify phonetic fields with one explicitly authorized Japanese contact
  apply and read-back test (`xvk-test-contacts-001`)

## 0.2.0 CTO release audit TODO

This is the release-blocking audit for the public `0.2.0` release. Each item
must record its scope, verification result, and remaining limitations before it
is checked off. These are local/manual checks; they do not add CI or authorize
automatic commit, push, or release actions.

### Required: release blockers

- [x] **Freeze the 0.2.0 scope**: document Mail as read-only; no send, reply,
  move, archive, delete, flag, or account mutation. Keep CLI help, README,
  usage docs, and CHANGELOG consistent; add negative tests for unsupported writes.
- [x] **Audit version consistency**: `VERSION`, CLI `--version`, both source
  and app `Info.plist` files, CHANGELOG, the public `v0.2.0` Release asset,
  and the public Tap Formula all report 0.2.0. Source Release and installed
  binaries were verified separately; the installed Homebrew binary was
  upgraded from 0.1.4/0.1.5 and reports 0.2.0.
- [x] **Run the complete local test matrix**: Swift tests (87 passed), CLI
  contract and negative-path tests, Mail release gate, Mail Automation/GUI
  gate, independent Release build, and installed-binary smoke test all passed.
  The unsigned binary required the documented local quarantine removal before
  the installed smoke test could execute.
- [x] **Confirm the macOS 26+ baseline**: record macOS, Xcode, SDK, and Swift
  versions; the current macOS 27.0 (`26A5388g`) / Xcode 26.6 / SDK 26.5 /
  Swift 6.3.3 run is forward-compatibility evidence, while the recorded macOS
  26.4 Release verification remains the formal baseline evidence.
- [x] **Complete the Mail permission failure matrix**: stable errors and recovery
  guidance for FDA denial, Automation denial, Mail not running, active sync, and
  unreadable stores; verify with controlled local permission states. The local
  doctor/metadata/release gate and GUI-session Automation smoke passed with FDA
  and Automation available; `target_not_running` and `requires_consent` were
  also observed as structured states.
- [x] **Fail closed on unknown Mail schemas**: only enable runtime-recognized
  schemas; unknown `V*` versions and missing tables must return a structured
  `MAIL_SCHEMA_UNSUPPORTED`-class error. The eight `MailDoctorTests` cases pass,
  covering unknown schemas, missing structures, unavailable fallback, and error
  mapping.
- [x] **Audit the read-only boundary**: SQLite, WAL/SHM, EMLX, and account
  configuration must never be written, moved, deleted, or modified. Review write
  APIs and compare file metadata/hashes before and after smoke tests. The audit
  confirmed `SQLITE_OPEN_READONLY` plus `query_only=ON`, read-only EMLX handles,
  and unchanged Envelope Index/WAL/SHM hashes and metadata around the local
  metadata smoke.
- [x] **Lock the JSON contract and exit codes**: stabilize the meaning of
  `contractVersion`, backend/cache/completeness fields, limitations, error codes,
  and exits; Swift and Mail fixture tests cover success, denial, unsupported
  schema, timeout, empty/fallback results, pagination, and stale opaque IDs.
  Local process checks confirmed success JSON on stdout, error JSON on stderr,
  query exit 0, stale-ID exit 4, and unsupported-command exit 64.

- [x] **Unify account / container / source capabilities**
  - Goal: define a shared read-only resource description, stable opaque ID,
    display name, type, capabilities, and permission state for Contacts iCloud
    containers, Mail account scopes, and EventKit Calendar/Reminders sources.
  - Personal selection policy: Contacts prefers the personal iCloud container;
    Calendar and Reminders prefer the personal iCloud source; Mail prefers the `aim-tech.jp`
    work account and does not default to iCloud Mail.
  - Scope: unify the Core contract, capability reporting, and verifiable
    selection policy only. Do not hard-code an Apple ID, email address, or
    internal account identifier into the public contract, and do not pretend
    these Apple objects are identical.
  - Verification: each adapter can list resources and report `readable`,
    `writable`, `selected`, and `permission`; unavailable resources return
    structured errors; opaque IDs do not expose email addresses, account URLs,
    or internal database paths. Missing or ambiguous preferred resources must
    stop rather than silently switching accounts.
  - Implemented: `macos-data resources --format json` lists verified Contacts
    containers, privacy-safe Mail account scopes, and EventKit Calendar/Reminders sources.
    Contacts, Calendar, and Reminders select only uniquely verified personal iCloud
    resources. Mail remains unselected unless the preferred work account can be
    verified without exposing account data.

- [x] **Cross-adapter pagination protocol**
  - Goal: give Contacts, Mail, and Calendar consistent semantics for `limit`,
    opaque `cursor`, `truncated`, `nextCursor`, `complete`, and result caps so
    Agents can process pages and resume after interruption.
  - Scope: define the Core contract first, then implement it in Mail and future
    Contacts/Calendar commands. Cursors remain backend-specific and opaque;
    expired cursors return a structured stale-cursor error.
  - Verification: synthetic fixtures cover first/last page, repeated and stale
    cursors, result caps, stable ordering, and bounded memory usage.
  - Implemented locally: Core `PagedResult`/`Pagination` semantics, Contacts
    `list`/`query` pages, Mail's canonical `items` field, and fail-closed stale
    cursor validation. The legacy Mail `messages` field remains as a
    compatibility alias; Mail.app fallback explicitly has no resumable cursor.
  - Verification: Core, Contacts, SQLite Mail, and Mail.app fallback fixtures
    cover first/last page, opaque cursor round-trips, invalid/stale cursors,
    result caps, and incomplete fallback semantics.
- [x] **Verify the public Homebrew Cask**: the historical 0.2.0 Cask was
  installed and used, and the current 0.3.0 public asset was reinstalled from
  the Tap with URL, SHA-256, archive layout, managed symlink, `--version`, and
  installed smoke verification. Independent clean-Mac testing remains above.
- [x] **Document unsigned-distribution limits**: without an Apple Developer
  Program, document Gatekeeper warnings, manual approval, SHA-256 verification,
  and the fact that installation is not frictionless. The local Release binary
  was confirmed ad-hoc signed and rejected by `spctl --assess`; INSTALL now
  records the checksum-first and no-global-Gatekeeper-disable boundaries.

### Optional: does not block 0.2.0

- [x] Full-text mail search with explicit privacy, size, and timeout limits.
  - Implemented as `mail search --text <text>` over cached EMLX only; capped at
    200 candidates and one second, with structured cache limitations and no
    Mail.app/remote fallback.
- [x] Explicit attachment export with safe output handling, no overwrite, and
  path-traversal protection.
  - Implemented as `mail attachments export --id <id> --output <directory>`;
    cached EMLX only, unsafe filenames rejected, existing files preserved, and
    each attachment capped at 20 MiB.
- [ ] Mail writes such as send, reply, move, archive, delete, and flagging in a
  separate version design.
- [ ] Additional Mail schema support, each with its own fixture and runtime gate.
- [x] Message-thread/conversation modeling after validating stable source data.
  - Added read-only `mail threads`; only explicit positive `conversation_id`
    values are grouped, with opaque IDs and no subject/participant inference.
- [x] Large-mailbox performance and memory benchmarks using synthetic data.
  - Added a manual 5,000-record SQLite fixture benchmark using XCTest clock and
    memory metrics. It is not CI and does not gate releases; future numbers must
    be compared on the same hardware/toolchain.
- [x] **Reject incremental change detection for now**: do not add snapshots,
  change tokens, system notifications, or an extra Agent memory layer. Prefer
  direct, bounded, repeatable current-state queries. Revisit only after a clear
  performance or synchronization requirement and a separate architecture audit.
- [x] **Reject Intel Mac support**: the project is officially Apple Silicon
  (arm64)-only. Do not evaluate Intel builds, Rosetta behavior, or x86 Homebrew
  assets unless the platform strategy is separately redesigned and audited.
- [ ] MCP/Agent wrapper evaluation after the CLI contract remains stable; do not
  bind the CLI to one Agent platform.

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
- [ ] Add cross-adapter batch operations; incremental change detection is
  explicitly out of scope unless separately re-approved.
- [x] Version the shared JSON contract independently from the CLI release

Each adapter should define its own authorization requirements, model mapping, read/write capabilities, errors, and tests.

## Remaining design details

- [x] Define the canonical external ID URL as
  `x-macos-data://external-id/<id>` with URL label `macos-data-cli`
- [x] Identify the unique iCloud-capable Contacts container and fail closed when
  it is missing or ambiguous
- [ ] Define structured warning output when `metadata` cannot be mapped to an
  Apple framework field
- [x] Keep destructive confirmation phrases command-specific and independent of
  mutable display names
- [x] Define and run the macOS 26 baseline / macOS 27 development compatibility
  and authorization regression matrix

## Out of scope for now

- GUI automation and screen-coordinate workflows
- Apple private APIs
- Writes to internal macOS databases; the Mail adapter permits only its
  documented, replaceable, strictly read-only local-index path
- Cloud uploads or centralized contact synchronization
- A built-in AI agent
- Coupling to one agent platform
- Making Obsidian a required part of the public data contract
