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

### 0.7.0: Stable Shortcuts runtime and organization

Version boundary: use only `/usr/bin/shortcuts`, the Shortcuts URL scheme, and
the public `Shortcuts Events` scripting dictionary. Do not read or mutate the
private Shortcuts database and do not edit action graphs.

- [x] Implement `shortcuts list` and `shortcuts get`
  - Return opaque shortcut ID, name, folder, subtitle, color, icon, input
    acceptance, and action count. Names are not stable identity, and the
    contract must not claim to expose actions or parameters
  - Add bounded pagination, stable ordering, strict JSON, structured
    Automation/helper errors, and privacy-safe diagnostics
  - Metadata/opaque-ID/pagination coverage passes within the Shortcuts
    synthetic tests. The read-only live gate returned two shortcuts, six folders,
    `complete=true`, and a successful opaque-ID get without printing user fields
- [x] Implement `shortcuts run`
  - Accept an explicitly selected shortcut ID, file/stdin input, and bounded
    output. Mark prompt-driven shortcuts as unsuitable for unattended Agents
  - Define deadlines, cancellation, output limits, and no automatic retry after
    `outcome_unknown`
  - The opaque-ID system CLI bridge, 16-input cap, 1...300-second deadline,
    256-KiB inline UTF-8 cap, no-overwrite file output, SHA-256, and exact
    confirmation phrase are implemented and pass synthetic/negative contracts.
    The disposable live fixture returned the exact 28-byte plaintext sentinel
    and verified its SHA-256. Plaintext is captured from the system CLI's stdout
    because `--output-path` is not applicable to this text result
- [x] Implement `shortcuts folders` and `shortcuts move`
  - Return opaque folder IDs. Move requires shortcut and destination folder IDs
    and must never infer either object from a display name
  - Default to dry-run, re-read source/destination before apply, verify folder
    identity after the write, and treat the same folder as a safe no-op
  - Folder discovery, filter-bound pagination, move preview/no-op, raw-ID
    mutation bridge, and immediate read-back are implemented. The live fixture
    passed preview, apply/read-back, destination get, restoration, and final
    source-folder get
- [x] Complete synthetic TDD, CLI negative contracts, and a disposable live gate
  - Cover helper failure, Automation denial, stale IDs, duplicate names,
    timeout, output truncation, and diagnostic redaction
  - Verify list/get/run/move/read-back with a dedicated fixture and restore its
    original folder afterward; never execute an existing user shortcut
  - Completed with one purpose-built two-action text fixture and two explicit
    test folders. Cleanup left zero fixture shortcuts/folders and restored the
    original two shortcuts and six folders with `complete=true`
  - Cold-start regression coverage allows the actual bridge to launch the
    on-demand Shortcuts Events helper instead of rejecting an idle helper before
    the Apple Event is sent
  - The 0.7.0 release gate passed version consistency, the full Swift suite,
    Release and signed-Debug builds, shared CLI/Calendar contracts, and Mail
    doctor/metadata/content/attachment smoke tests. Calendar live smoke retained
    its stable fail-closed result because this host has multiple matching iCloud
    sources; no Calendar write was attempted
  - A byte-identical candidate was installed alongside the Homebrew-managed
    0.6.2 command as `/opt/homebrew/bin/macos-data-0.7.0-rc`. The final combined
    gate passed with `installedSmoke=true`, including version 0.7.0, Calendar and
    Shortcuts contracts, and the Mail SQLite fast path. The canonical Homebrew
    symlink remains unchanged until a separately authorized public release

### 0.7.1: Cherri managed-source authoring

Version boundary: create and update only shortcuts whose `.cherri` source is
the SSOT and whose identity is tracked by the macos-data registry. Invoke Cherri
as an optional external compiler without copying its GPL-2.0 source. Clearly
label the undocumented Apple Shortcut file format as experimental and gate each
supported macOS/Shortcuts version independently.

- [x] Implement `shortcuts author validate` and `shortcuts author build`
  - Validate Cherri availability, source size, allowed includes/packages,
    sensitive-value rules, and target action definitions
  - Build in a private temporary directory, sign through the system
    `shortcuts sign`, and return source/compiled SHA-256, action count, and
    signing mode without emitting source, parameters, or secrets
  - Cherri 2.3.0 validate/build and system signing passed on macOS 27 Beta 5;
    the non-importing gate also verifies mode `0600`, no overwrite, and result
    redaction. Byte-only source copying avoids inherited `com.apple.provenance`
    that otherwise causes the system signer to reject the generated artifact
- [x] Implement guarded `shortcuts create`
  - Default to dry-run. Apply requires an exact confirmation phrase and performs
    a visible import through Shortcuts.app
  - Use a short-lived idempotency receipt and verify the imported opaque ID,
    name, action count, and explicit smoke input/output
  - Runtime, receipt, confirmation, dry-run, redaction, registry integration,
    visible import, and exact black-box sentinel output passed
- [x] Implement guarded `shortcuts update`
  - Accept only a managed shortcut already present in the registry and require
    an expected source hash. Never silently adopt an arbitrary user shortcut
  - Because Apple exposes no in-place action-graph replacement API, initially
    compile, import, and verify a candidate before explicit replace/retain-old
    confirmation. Never delete the old version first
  - Managed-only concurrency, retain-old packaging, no-auto-retry, and atomic
    registry identity replacement passed. Replace fails closed when public and
    compiled counts differ, as observed on macOS 27 Beta 5
- [x] Add a private local registry and complete live gate
  - Store only opaque shortcut ID, source/compiled hashes, action count, version,
    and timestamps. Use directory mode `0700`, file mode `0600`, and atomic
    writes; never retain action parameters, source, tokens, or other secrets
  - The registry implementation and its `0700`/`0600`, atomic-write, validation,
    redaction, managed-list, and non-deleting forget tests are complete
  - A disposable fixture must cover validate, build, sign, import, run, source
    modification, re-import, read-back, and cleanup. Re-run the gate after each
    major macOS/Shortcuts update
  - The macOS 27 Beta 5 / Cherri 2.3.0 gate passed with create, exact sentinel
    run, retain-old update, second exact run, semantic UI cleanup, and zero
    fixture/registry residue. Shortcuts Events reported `0` actions for both
    working imports, so compiled and observed counts remain separate fields

### 0.7.2: Experimental editing of arbitrary existing shortcuts

Version boundary: modify shortcuts that were not created by macos-data. Apple
currently exposes no public action-graph CRUD API, so this version must remain
explicitly experimental, permission-gated, and fail closed, with no promise of
cross-version stability.

- [x] Add safe local acquisition and capability classification
  - `shortcuts edit inspect --input <local.cherri|local.shortcut>` reads one
    explicit non-symlink regular file through `O_NOFOLLOW`, caps input at
    10 MiB, and returns only SHA-256, byte/count metadata, risk flags, and
    stable capability/reason enums
  - Reject or require manual Shortcuts.app migration for signed files that
    cannot be decoded reliably, unknown actions, device-bound references,
    secrets, or unsupported structures. Never access SQLite, CloudKit, or a
    private framework
  - Twelve focused tests and process-level no-apply CLI contracts cover bounded
    unsigned input, opaque input, Cherri routing, redaction, symlinks, size,
    unknown actions, secrets, device-bound references, and nested magic-variable
    or attachment structures. Semantic apply remains disabled
- [x] Add a redacted action-level edit-plan contract
  - `shortcuts edit plan` requires an exact input SHA-256 and strict JSON, then
    validates up to 64 sequential insert-text, replace-text, delete-action, and
    move-action operations against an in-memory shadow graph
  - Eight focused tests plus process-level contracts cover strict fields,
    conflict detection, bounds, action-type safety, redaction, and zero input
    mutation. No apply, Apple Event, Accessibility event, or artifact output is
    reachable
- [x] Evaluate iCloud share-link acquisition separately and keep it disabled
  - Apple documents that creating an iCloud link sends Apple a copy for
    validation and makes the link available through iCloud. Receiving a link is
    a visible Get Shortcut/import flow, not a documented headless graph API
  - 0.7.2 accepts only explicit local `.cherri`/`.shortcut` paths. It performs no
    share-link request, download, redirect, clipboard read, or import
  - The reader now requires `isFileURL`; a red/green regression proves an HTTPS
    URL whose path aliases a real local fixture is rejected before reading. The
    CLI also rejects URI syntax and never echoes the supplied link
  - Reconsider only through a future opt-in command with an action-time privacy
    confirmation, bounded download, redirect/domain policy, and separate visible-import contract
- [x] Add bounded read-only semantic Accessibility discovery
  - Locate controls only by AX role, identifier, label, and hierarchy. Prohibit
    screen coordinates, image matching, and unbounded clicking
  - `shortcuts edit ui-inspect` checks trust without prompting, does not launch
    or activate Shortcuts.app, caps traversal at 2,000 nodes/depth 32, returns
    counts only, and fails closed on generic, ambiguous, or unbounded trees
  - Eight synthetic tests plus no-apply CLI contracts prove zero action API,
    permission/target states, ambiguity, bounds, semantic-marker requirements,
    and label/title/identifier redaction. Semantic apply remains disabled
- [x] Validate read-only AX discovery with a disposable macOS 27 Beta 5 fixture
  - The initial live run failed closed because Shortcuts 27 exposes the editor
    marker as `editor.shortcutname`; a red test captured that compatibility gap
    before the exact normalized marker was added to the allowlist
  - The calibrated run returned one bounded editor candidate across two windows
    and 373 nodes while keeping labels, titles, identifiers, and action text out
    of JSON. After semantic UI deletion, unique-name search returned no results
    and CLI discovery returned zero editor candidates across one window/139 nodes
- [x] Calibrate exact Text/Comment semantic elements on macOS 27 Beta 5
  - A second local-only fixture established the unique `editor.shortcutname`
    field, the outer action canvas, direct Text/Comment titles, Close buttons,
    nested scroll areas, and one settable text area per supported action
  - A pure semantic resolver ignores the separate action-library scroll area,
    hashes all private values, and fails closed on unknown actions, malformed
    fields, ambiguity, or traversal bounds. Four focused tests cover this graph
  - Read-only menu inspection recorded `duplicateShortcut:`,
    `duplicateAction:`, `rearrangeItemUp:`, `rearrangeItemDown:`, and
    `insertCommentAction:` as version-specific evidence only. No action was
    invoked, and cleanup restored the original library count with zero name hit
- [x] Design guarded semantic Accessibility mutation
  - A pure coordinator consumes the implemented action-level edit plan, requires
    exact `EDIT SHORTCUT COPY` confirmation before any editor read, and preflights
    the complete operation sequence before creating a recovery object
  - Mutation is copy-first: the recovery candidate must have a distinct hashed
    identity and an exact initial semantic graph match. Every operation requires
    exact read-back; errors or mismatches return `outcome_unknown`, preserve the
    original, and prohibit automatic retry
  - Ten focused tests cover preview isolation, confirmation, ambiguity,
    concurrency, full-plan preflight, recovery-copy proof, sequential read-back,
    unknown outcomes, and result redaction
  - Strict patch parsing now produces a non-Codable, redacted-debug in-memory
    execution plan beside the public plan. The coordinator verifies every
    private text value against its byte count and SHA-256 before reading AX state;
    a summary alone is never executable. Edit-plan and coordinator suites now
    contain ten and eleven focused tests respectively
  - A plan-bound guarded bridge exposes only inspect, duplicate, insert/replace
    text, delete, and move session methods. It enforces recovery-first exact
    sequence, rejects altered/extra operations, becomes permanently poisoned
    after a session mutation error, and has five focused tests
  - No generic AX action API is reachable; each public copy-first operation
    remains separately gated below
- [x] Pass the first concrete copy-first `replace_text` gate
  - This first gate allowed only exact `duplicateShortcut:` and Text-area value
    replacement; insert/delete/move were hard-disabled at that point. Five
    focused tests covered the session and confirmed existing-copy recovery
  - The bounded driver reads only the toolbar name and action canvas, selects
    exactly one main/focused editor, and applies a five-second AX deadline
  - A macOS 27 Beta 5 fixture proved copy identity, graph equality, replacement
    hash read-back, unchanged Comment, and unchanged original. A fail-closed
    two-window outcome resumed the already verified copy without duplicating it
  - Both fixtures were permanently deleted after separate confirmation; the
    library returned from four to two and exact-name search returned no results
  - The fixture harness is debug-only; it is not a public recovery interface
- [x] Expose the proven copy-first `replace_text` route through a guarded CLI contract
  - `shortcuts edit copy` requires one local artifact, one strict patch, the
    exact visible editor-name SHA-256, and exactly one of dry-run/apply
  - Dry-run returns before constructing the system AX bridge. Apply requires
    exact `EDIT SHORTCUT COPY` confirmation before bridge construction
  - This gate initially enabled replace-text-only plans; the append-only gate
    below subsequently extends the same contract. Other insert/delete/move
    operations fail with a stable unsupported-capability error before mutation
  - Six service tests plus process-level CLI contracts cover preview isolation,
    confirmation, hash/mode validation, unsupported-operation rejection, and
    output redaction. No additional live fixture was created for this wiring
- [x] Prove and expose append-only `insert_text` on a verified copy
  - The only enabled insertion index is the current action count, and the graph
    must already contain a resolver-approved Text action. Middle insertion and
    insertion into a graph without Text fail before mutation
  - The bounded driver focuses only that known Text field and invokes the exact
    `duplicateAction:` Edit menu identifier. It verifies one appended duplicate,
    changes only its value, and reads back the complete semantic graph
  - A macOS 27 Beta 5 fixture proved Text + Comment became Text + Comment + Text
    only in the copy, while the original stayed unchanged. The result was
    `readback_confirmed`, with three verified actions and no private values in JSON
  - The delete gate, stale-read-back recovery, and mixed-family guard bring
    ShortcutsTests to 105/105; focused coverage includes 12 acquisition,
    13 edit-plan, 11 coordinator, 7 service,
    5 guarded-bridge, 4 resolver, and 9 system-session tests
  - After separate confirmation, both fixtures were deleted through Shortcuts UI;
    All Shortcuts returned from four to two and both exact-name searches returned no results
- [x] Prove and expose copy-first `delete_action` with disposable fixtures
  - Synthetic implementation resolves exactly one `Close` AXButton per supported
    action, rejects a graph that would become empty, presses only the bound path,
    and relies on coordinator read-back of the complete post-delete graph
  - Plan, public dry-run, and guarded apply are wired and redacted. Apply accepts
    only all-delete plans that leave at least one action
  - A debug-only `copy-delete` harness is ready to verify Text + Comment becomes
    Text only in the copy while the original remains unchanged
  - [x] An authorized macOS 27 Beta 5 Text + Comment fixture proved that only
    the copy lost its Comment, the copy read back as one unchanged Text action,
    and the original read back as the original Text + Comment graph
  - [x] The first post-delete read-back exposed a real stale-graph window. The
    command failed closed without retry; a read-only existing-copy recovery
    confirmed the mutation, and a red/green test now requires delete to poll
    until the exact smaller graph is stable
  - [x] Both fixture objects were removed from All Shortcuts; the count returned
    from four to two and exact-name search returned no results
  - [x] A second disposable fixture passed the corrected uninterrupted gate in
    one command, then original verification also passed
  - [x] After explicit permanent-delete confirmation, both second-gate objects
    were deleted; All Shortcuts returned from four to two and exact-name search
    returned no results
- [x] Support a constrained set of existing-object edits through a verified copy
  - [x] Prove copy-first `move_action` with one disposable Text + Comment fixture:
    duplicate, move Comment from index 1 to 0 through exact `rearrangeItemUp:`,
    read back Comment + Text, then independently verify the original remains
    Text + Comment. Synthetic adjacent-step polling and fail-closed equal-action
    guards are complete. The gate exposed stale ordinary `AXChildren` ordering;
    verified `AXChildrenInNavigationOrder` plus top-left-coordinate Y ordering
    now provides complete visual-order read-back. The moved copy and unchanged
    original both passed hash-bound read-back; public all-move apply is enabled
  - [x] After separate action-time confirmation, permanently deleted the original
    and recovery-copy move fixtures; All Shortcuts returned from four to two and
    both exact-name searches returned no results
  - Continue with an allowlist of verified action delete/reorder and additional
    parameter replacement operations. Control flow, magic variables,
    third-party actions, and device-bound references each require separate
    fixtures before enablement
  - Use shortcut ID, expected action count, and available metadata as concurrency
    guards. Since the public interface cannot read a complete action graph, do
    not claim full transactions or lossless round trips
  - Re-evaluate the wording `in-place`: the approved coordinator edits only a
    verified copy and preserves the original. Direct original-object mutation
    stays disabled unless a separate rollback proof becomes possible
- [x] Complete the macOS 27 Beta 5 UI fixture and recovery gates for the 0.7.2 surface
  - Disposable fixtures proved copy-first replace-text, append-only insert,
    bounded delete, and bounded all-move while preserving the original
  - Every apply creates or resumes a distinct verified copy, reads back the
    complete supported semantic graph, and returns `outcome_unknown` without
    automatic retry when the result cannot be proved
  - All disposable fixtures were permanently deleted after separate
    action-time confirmation, and exact-name searches returned no results
- [ ] Re-run the version-specific semantic fixture gate before claiming support
  for a future macOS/Shortcuts version; 0.7.2 makes no cross-version guarantee

### 0.8.0: Safari bookmarks and Reading List

Architecture: [Safari adapter 0.8](docs/development/safari-adapter-architecture.md).

- [x] Audit Safari 27 public interfaces and live storage without modifying data
  - Safari's scripting dictionary exposes Reading List addition but no bookmark
    CRUD or Reading List read/update/delete commands
  - The live canonical store is `~/Library/Safari/Bookmarks.plist`; Bookmarks
    and Reading List are not stored canonically in the inspected Safari SQLite files
- [x] Implement bounded, read-only bookmark and Reading List snapshots
  - Foundation property-list parsing supports binary/XML input, 32 MiB, 50,000
    nodes, and depth 64, with fail-closed schema validation
  - Raw UUIDs are hash-derived opaque IDs; proxy and Reading List nodes do not
    leak into ordinary bookmarks; titles, URLs, previews, UUIDs, and paths never
    enter diagnostics
  - Query uses AND filters, maximum 200 pages, and cursors bound to both filters
    and exact plist SHA-256 so changed Safari state makes cursors stale
- [x] Add `safari permission`, bookmark list/query/get, and Reading List
  list/query/get commands with exit 10 and the shared JSON contract
- [x] Implement guarded Reading List add
  - Strict stdin/file JSON, HTTP/HTTPS-only URL, bounded title/preview, explicit
    dry-run/apply, normalized-URL no-op, five-second Safari Apple Event, immediate
    plist read-back, and pending/unknown no-auto-retry states
  - AppleScript syntax passed a compile-only local check; no real item was added
- [x] Pass synthetic TDD, no-apply CLI contracts, and privacy-minimized live
  list/get plus add dry-run smoke on Safari 27; temporary private JSON was removed
- [x] Request the stable Debug app's Safari Automation permission and run one
  explicitly authorized disposable Reading List add/read-back/UI-cleanup gate
  - The Apple Event returned `save_accepted_readback_pending`, so the CLI did
    not retry. A subsequent exact-URL query found one opaque Reading List item
  - After separate action-time confirmation, Safari UI removed only the exact
    filtered fixture; both UI search and exact-URL CLI query returned zero matches
- [x] Run the complete Swift suite, Release/no-apply gates, and documentation audit
- [x] Update source version metadata from 0.7.2 to 0.8.0 after all local gates;
  commit/push/tag/release still require separate authorization

### 0.8.1: Local-only Safari bookmark mutation

The previously separate 0.8.1 feasibility, 0.8.2 safety-engine, and 0.8.3 CRUD
development milestones are consolidated into the public 0.8.1 source release.
Their historical gate names remain unchanged as evidence; the shipped contract
is the guarded local-only CLI and never implies iCloud synchronization.

- [x] Prove semantic parser/serializer round trips on synthetic fixtures and an
  auto-deleted private copy of the live plist
  - Unknown plist values, ordered children, mode, owner, group, and every source
    xattr value are preserved; symlinks, overwrite, duplicate UUIDs, unknown node
    types, and changes outside the selected ancestry fail closed
  - The live binary plist is not byte-identical after Foundation serialization
    (914,933 to 914,917 bytes), so safety uses typed canonical hashes for every
    untouched subtree rather than whole-file byte equality
  - macOS attaches destination-only `com.apple.provenance` when the test carrier
    rewrites the private copy. It is reported explicitly; any other added xattr
    fails the gate. The live source remained byte-for-byte unchanged
- [x] Implement and locally audit the attended quiescence/backup gate
  - Reject a running Safari application or any process holding the exact plist;
    require matching device, inode, size, mtime, mode, owner, group, SHA-256, and
    xattr-value hashes across two snapshots separated by 500 ms
  - Create an exact recovery copy and privacy-safe JSON manifest in a mode-0700
    directory with both files mode 0600, then re-check quiescence and an identical
    third source snapshot; incomplete artifacts are automatically removed
  - The live read-only audit passed with Safari exited, no open handles, exact
    0600 recovery data, and an unchanged source; its temporary recovery directory
    was automatically deleted. The gate must run again immediately before the
    separately authorized mutation and is not reusable as a stale approval
- [x] Execute one attended atomic disposable-bookmark mutation and verify the
  fixture in Safari UI and through the 0.8 parser
  - Pre-live TDD is complete: the writer rejects stale/tampered recovery state,
    creates a same-directory candidate, re-applies exact source xattr values,
    uses `RENAME_SWAP`, verifies both new and old sides, and swaps back on any
    read-back failure
  - An auto-deleted copy of the live Safari schema successfully added exactly one
    bookmark under the unique built-in `BookmarksBar`; 206 untouched subtrees
    retained their canonical hashes and the real source remained unchanged
  - Session `3f6c5b6f-aa0c-4a21-98e8-fe66c578a781` added exactly one fixture;
    Safari UI and the public CLI both found it, and 0600 recovery remains retained
  - Reading List changing from 89 entries to zero was a separate manual deletion
    by the user, not an effect of the fixture write. It is excluded from the
    mutation-safety verdict
- [x] Test a second iCloud device and record that the fixture did **not** appear;
  direct plist replacement therefore proves local mutation only and does not
  produce Safari's private iCloud change transaction
- [ ] Remove only the disposable fixture through a Safari-owned route and prove
  deletion on both devices, with no duplicates, resurrection, missing old nodes,
  schema drift, or sync errors
- [x] Record a split decision: **local-only go, iCloud-sync no-go**. Do not claim
  cross-device persistence and do not restart private sync daemons as a substitute
  for a supported Safari mutation
- [x] Add an explicit local-only contract and warning before exposing direct-plist
  writes: `syncStatus=local_only`, retained recovery, and a `nextAction` explaining
  that Safari-owned import is required for an iCloud-synced copy

#### Internal safety-engine milestone included in 0.8.1

- [x] Productize the guarded direct-plist mutation foundation as an explicitly
  local-only engine; never imply that it updates iCloud
  - The detailed local CRUD contract and the useful design ideas audited from
    Apache-2.0 `safari-bookmarks-mcp` are assigned to 0.8.3 below
  - Do not adopt its weaker persistence path: macos-data must retain Safari quit
    and open-handle gates, optimistic source identity/hash, metadata/xattr
    preservation, fsync, rollback, private recovery, and live read-back
- [x] Expose reusable prepare/apply/read-back/rollback primitives to the Safari
  adapter, with privacy-safe receipts and stable local-only result/error codes
- [x] Complete synthetic and private-live-copy TDD for stale source, concurrent
  change, interrupted write, rollback failure, metadata drift, and safe no-op

#### Internal CRUD milestone included in 0.8.1

- [x] Adapt the useful **contract concepts**, not the persistence implementation,
  from Apache-2.0
  [`chikingsley/safari-bookmarks-mcp`](https://github.com/chikingsley/safari-bookmarks-mcp)
  into an independently implemented macos-data adapter
  - Use opaque UUID targeting for existing nodes and explicit parent UUID plus
    child index for placement; permit a human-readable path only for discovery
    and dry-run display, never as an ambiguous write identity
  - Define strict JSON contracts for bookmark add/edit/move/remove and folder
    create/rename/move/remove; reject unknown fields, duplicate UUIDs, invalid
    indexes, missing parents, root mutation, and bookmark/folder type mismatch
  - Reject moving a folder into itself or one of its descendants, and reject
    deleting a non-empty folder unless the request uses a separate recursive
    operation with an exact destructive confirmation phrase
  - Make every mutation dry-run by default. `--apply` must require the current
    source identity/hash token, return changed node/parent opaque IDs, and report
    `syncStatus=local_only` plus an explicit iCloud limitation/next action
- [x] Keep macos-data's stronger persistence and privacy gates instead of
  adopting the reference project's direct read-modify-write behavior
  - Require Safari fully quit, no open handle, stable repeated snapshots,
    optimistic source identity/hash, private `0700` recovery, `0600` backup and
    receipt, exact metadata/xattr preservation, same-directory atomic swap,
    fsync, bounded read-back, rollback, and diagnostics redaction
  - Preserve unknown plist fields and untouched subtree ordering/hashes; a
    mutation outside the selected node ancestry must fail closed
- [x] Build the feature with TDD and staged evidence
  - Unit fixtures cover every CRUD operation, path/UUID resolution, cycle and
    recursive-delete refusal, strict JSON, stale token, no-op, rollback, schema
    drift, and privacy-safe diagnostics
  - [x] A private copy of the live plist passed create → edit → move → remove and
    folder create → rename → move → empty-delete with zero residue
  - [x] One explicitly authorized disposable live fixture passed create plus
    Safari UI/CLI read-back, then bookmark edit/move/delete and folder
    rename/move/empty-delete. Final read-back found zero fixture residue, the
    Reading List unchanged, and all 117 pre-existing nodes identical except
    Safari's normalization of its two built-in root titles

The combined 0.8.1 source release is the target after its local CRUD and release
gates pass. It does not depend on iCloud synchronization, and the shipped
binary must not call private Safari frameworks or sync daemons.

### 0.8.8: Safari iCloud synchronization research

- [x] Record the current no-go evidence
  - Direct plist replacement was visible locally but produced no
    `Sync.Changes` record and did not appear on the second device
  - A private `WebBookmarkGroup` create/save did produce exactly one matching
    `Sync.Changes` `Add`; the one-argument sync request was called exactly once,
    but the fixture still did not appear on the second device
  - After the failed remote read-back, the private fixture was UUID-resolved,
    removed, saved, locally verified at zero matches, and issued exactly one
    cleanup sync request. No automatic retry or daemon restart was performed
- [ ] Revisit sync only after the local CRUD release is stable. Separately
  evaluate Safari-owned HTML import, Shortcuts Safari actions, shipping Safari
  WebExtension capability, and semantic non-coordinate Accessibility
- [ ] Any future private-framework experiment requires a new explicit
  authorization, disposable fixture, fresh recovery, compatibility/signing
  audit, one-attempt receipt, second-device create/delete read-back, and zero
  residue. A private selector or local `Sync.Changes` record is not sync proof
- [ ] Do not expose an iCloud-syncing contract until one supported or explicitly
  accepted route passes repeated cross-device create, update, move, delete,
  conflict, duplicate, and recovery gates

### 0.9.0: Phone and Messages CLI feasibility

- [ ] Investigate whether macOS Phone/FaceTime and Messages can support safe,
  local, read-only CLI adapters for recent call history and recent messages
  - Inventory the supported macOS versions and actual installed applications;
    do not assume `Phone.app` exists or owns call history on every supported Mac
  - Audit public frameworks, application scripting dictionaries, Shortcuts
    actions, Apple Events, Continuity boundaries, and documented export paths
    before considering local stores
  - If public interfaces are insufficient, separately evaluate strictly
    read-only local database/index access with Full Disk Access, runtime schema
    fingerprints, immutable connections, bounded queries, and fail-closed
    compatibility. Do not implement or expose this fallback without a recorded
    architecture and privacy decision
- [ ] Define a metadata-first candidate contract without committing to it:
  `phone calls recent` for direction/time/duration/missed state and
  `messages recent` for service/direction/time/conversation and bounded text
  projection. Participant handles, message bodies, attachment paths, raw local
  IDs, and account identifiers require explicit projection and redaction rules
- [ ] Map TCC and user-consent behavior for Full Disk Access, Automation,
  Contacts resolution, Messages data, and Phone/FaceTime data. Permission status
  must not prompt; only an explicit request path may initiate ordinary consent
- [ ] Keep 0.9.0 research and any initial adapter read-only: no send/reply,
  call initiation, voicemail mutation, mark-read, reaction, attachment export,
  conversation deletion, or call-history deletion
- [ ] Produce a separate go/no-go decision for Phone/call history and Messages.
  Validate parsers only with synthetic fixtures; any live smoke must be
  privacy-minimized, bounded, separately authorized, and must not print personal
  handles or content

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

- General GUI coordinate automation and image matching. Version 0.7.2 may
  evaluate only a tightly scoped, semantic, explicitly experimental Shortcuts
  Accessibility backend
- Apple private APIs
- Writes to internal macOS databases; the Mail adapter permits only its
  documented, replaceable, strictly read-only local-index path
- Cloud uploads or centralized contact synchronization
- A built-in AI agent
- Coupling to one agent platform
- Making Obsidian a required part of the public data contract
