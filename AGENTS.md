# Agent Integration Guide

This repository is a CLI, not an Agent Skill. Agents and Skills that invoke
`mpia` should read these files before using it:

From 0.9.3 onward, every business invocation must use `mpia METHOD "/path"` with
strict inline `--params`/`--body` JSON. Only `--help`, `--version`, and `-v`
remain bootstrap forms. Discover the executable surface through
`mpia GET "/agent/manifest"`; never reconstruct or invoke the removed legacy
adapter/subcommand syntax. Inline JSON may be visible in shell history or
process arguments, so it must never contain credentials or other secrets.

0. `https://mpia-cli-doc.vercel.app/` for the hosted, searchable command
   reference; repository Markdown remains the auditable source of truth
1. `README.md` or `README_CN.md` for the supported command surface
2. `docs/usage.md` or `docs/usage_CN.md` for command details and examples
3. `docs/development/rules.md` or `docs/development/rules_CN.md` for safety rules
4. `docs/development/cli-contract.md` or its Chinese version for JSON and exit codes
5. `docs/development/local-debug-and-tcc_CN.md` for local Xcode, Debug app, and
   Contacts TCC authorization behavior

For Mail 0.2 planning or implementation, also read:

6. `docs/development/mail-adapter-architecture.md` (or the Chinese summary) for
   the read-only SQLite/EMLX boundary, Apple Events fallback, permissions,
   privacy rules, and compatibility gates
7. `docs/development/github-cli-environment.md` (or the Chinese version) before
   diagnosing GitHub CLI, Release, tag, or Homebrew Tap connectivity/authentication
8. `docs/development/rules.md` (or the Chinese version) for the rule that Codex
   should complete no-password authorization/settings flows and hand off only
   password, Apple ID, or security-confirmation steps

For Calendar 0.3 planning, implementation, or invocation, also read:

9. `docs/development/calendar-adapter-architecture.md` (or the Chinese version)
   for EventKit permissions, iCloud source selection, recurrence scope, opaque
   occurrence IDs, JSON fields, and the local smoke-test boundary

For Reminders 0.4 planning or implementation, also read:

10. `docs/development/reminders-adapter-architecture.md` and the Chinese version
    before changing Reminders contracts or runtime code

For Photos 0.5 planning or implementation, also read:

11. `docs/development/photos-adapter-architecture.md` and the Chinese version
    before changing PhotoKit permissions, metadata, album, export, or mutation
    behavior

For Shortcuts 0.7.1 authoring, also read:

12. `docs/development/shortcuts-authoring.md` or the Chinese version before
    compiling, signing, importing, registering, or updating a Shortcut
13. `docs/development/shortcuts-existing-editing.md` or the Chinese version
    before inspecting or planning edits for an arbitrary existing Shortcut
14. `docs/development/safari-adapter-architecture.md` or the Chinese version
    before reading Safari data, adding a Reading List item, or investigating
    direct bookmark mutation
15. `docs/development/messages-adapter-architecture.md` or the Chinese version
    before reading Messages data or changing the `messages` read-only boundary
16. `docs/development/phone-adapter-architecture.md` or the Chinese version
    before reading Call History data or changing the `phone-calls` read-only
    boundary

Shortcuts authoring rules:

- Cherri 2.3.x remains an optional external process; never bundle its GPL source
  or fall back to HubSign/remote signing.
- Create/update default to preview and may manage only `.cherri` SSOT records in
  the private registry. Never adopt an arbitrary existing Shortcut by name.
- Pending/unknown imports prohibit automatic retry. Inspect Shortcuts.app,
  metadata, receipts, and registry state first.
- Treat compiled `actionCount` and public `observedActionCount` separately.
  macOS 27 Beta 5 returned `0` for working Cherri imports; use an explicitly
  safe black-box run as graph proof, and reject same-name replace when counts
  do not establish a distinguishable transition.
- `managed forget` removes registry/receipt state only; it never deletes a
  Shortcut.
- `scripts/run_shortcuts_authoring_integration.sh` performs visible writes and
  requires explicit current-task authorization in addition to its exact outer
  confirmation. Cleanup is semantic UI deletion of the unique fixture followed
  by zero-residue read-back.
- `GET /shortcuts/edit/inspect` is read-only classification, not graph proof or edit
  authorization. It accepts only one bounded non-symlink local `.cherri` or
  `.shortcut`; never echo input names, source, action identifiers, parameters,
  or embedded values. Classification alone never authorizes apply.
- iCloud share-link acquisition is disabled in 0.7.2. Do not download links,
  follow redirects, read the clipboard, or reinterpret a URL path as a local
  file. The reader must require `isFileURL`; only a future separately confirmed
  opt-in network contract may revisit this boundary.
- `GET /shortcuts/edit/plan` is also read-only. Require the exact inspected input
  SHA-256 and strict JSON; evaluate indexes sequentially against the in-memory
  visible-action shadow graph. Never log or return text values, action IDs, or
  parameters. Apply capability is limited to replace-text-only plans,
  append-only insert-text plans whose graph already contains a Text action,
  bounded all-delete plans that leave at least one action, or bounded all-move
  plans; all
  must still pass the separate `edit copy` guards.
- All-delete apply must use the exact resolver-bound `Close` button, complete
  graph read-back, and an unchanged original. Never substitute a generic button
  press or mix delete with another operation family.
- After pressing a resolver-bound action Close button, wait for the exact
  smaller semantic graph; Shortcuts may briefly expose the stale pre-delete
  graph. A stale or unknown read-back is fail-closed and must never trigger an
  automatic duplicate or delete retry.
- `GET /shortcuts/edit/ui-inspect` may read only bounded AX attributes. It must not
  prompt, launch/activate Shortcuts.app, perform AX actions, use coordinates or
  image matching, or emit labels/titles/identifiers. Generic or ambiguous UI
  structure is not a candidate, and discovery never authorizes apply.
- The 0.7.2 semantic mutation coordinator underpins the public guarded
  `edit copy` replace-text, append-only insert, bounded delete, and bounded
  all-move routes. It must require exact `EDIT SHORTCUT COPY` confirmation,
  preflight the complete plan, prove a distinct graph-identical recovery copy,
  and read back every operation. Any bridge error or mismatch is
  `outcome_unknown` with no automatic retry. The concrete system session may
  perform only the proven copy-first Text replacement, append-only Text
  insertion, resolver-bound delete, or resolver-bound all-move plan. Append
  requires an existing resolver-approved Text action, exact `duplicateAction:`,
  and an index equal to the current action count. Move requires an all-move plan,
  exact resolver-bound reorder identifiers, and complete visual-order read-back
  after every adjacent step. Same-index moves, semantically indistinguishable
  adjacent actions, and plans mixed with another operation family fail closed
  before mutation.
- `PATCH /shortcuts/edit/copy --dry-run` must return before constructing the concrete
  system AX bridge. Apply requires the exact visible editor-name SHA-256 plus
  the confirmation phrase; output must remain value/title/path redacted and
  `outcome_unknown` must never be retried automatically.
- A semantic edit is executable only from the non-Codable in-memory execution
  plan produced by the same strict patch parse as the public redacted plan.
  Verify private value bytes/SHA-256 before any AX read. The guarded bridge must
  be bound to that exact plan, require recovery first, enforce exact operation
  sequence, and permanently reject retries after any session mutation error.
  Do not add generic AX click/type/coordinate APIs. A concrete Shortcuts 27 AX
  session requires fresh disposable-fixture authorization. Read-only calibration
  established the exact `editor.shortcutname` field and Text/Comment structure:
  direct action title plus Close button plus one nested settable text area. The
  action-library scroll area is always a decoy. Unknown titles, malformed value
  fields, ambiguity, and traversal overflow must fail closed. Recorded menu IDs
  are version-specific evidence only and never authorize invocation.
- Concrete AX selection must inspect only the exact toolbar name field and
  action canvas, never the complete action library. After duplication, select
  exactly one main/focused editor because the original editor remains open in
  the background. A confirmed existing-copy recovery may complete only a
  proven-not-yet-run replacement and must never duplicate again. Keep a
  five-second AX messaging deadline. Middle/no-source insert remains unsupported;
  same-index and semantically indistinguishable adjacent moves remain unsupported.
- Opaque/signed files, unknown actions, nested parameter structures (including
  magic variables and attachments), suspected secrets, and device-bound
  references require manual migration. Never inspect Shortcuts SQLite,
  CloudKit, or private frameworks to bypass that result.

## Current development executable

During local development, use the Debug app workflow described in
`docs/development/local-debug-and-tcc_CN.md`. Build the app with:

```text
bash scripts/build_debug_app.sh
```

The resulting authorized app is:

```text
.build/debug/mpia.app
```

`scripts/build_debug_app.sh` signs this bundle with
`scripts/mpia.entitlements`. Do not remove the
`com.apple.security.automation.apple-events` entitlement: the release gate reads
it back from the signed app and fails if it is absent or false.

For pure unit tests, `.build/debug/mpia` remains available. Skills should
allow the executable/app path to be configured with `MPIA_CLI`; they must
not assume a Homebrew or Release binary while development is in progress.

## Non-negotiable Contacts rules

- Contacts writes target the verified iCloud container only.
- Every CLI-created contact must have `external_id`.
- The external ID is stored only as URL label `mpia-cli` with value
  `mpia://ext-id/<id>`.
- Regular edit cannot change `external_id`; use the migration command.
- Writes require `--dry-run` or explicit `--apply`.
- Delete requires `--confirm "DELETE CONTACT"`.
- JSON responses use contract version `0.1`; branch on the process exit code first.
- Do not use `imageAvailable` as definitive GUI truth for iCloud avatars. For
  avatar writes, use `data.avatar.status`: `readback_confirmed` is strong
  confirmation; `verification_unknown` means the save was accepted but the
  framework could not read the image back. Follow `avatar.nextAction`; never
  auto-retry, delete, or recreate a contact.
- For a read-only existing-avatar check, use `OPTIONS /contacts/avatar/verify` with `external-id` in params;
  interpret `readback_confirmed`, `not_available`, and `verification_unknown`.
- Ambiguous matches must be reported, never silently selected.
- `metadata` is preserved in JSON but is not written to Contacts in 0.1.

## Non-negotiable Mail rules

- Run `OPTIONS /mail/doctor` before relying on direct-store reads. Enable SQLite only
  when `fastPathAvailable` is true; never infer support from the macOS version
  or a `V10` directory alone.
- Open `Envelope Index` strictly read-only and query-only. Never write the
  database, WAL/SHM sidecars, `.emlx` files, or Mail account configuration.
- Treat account, mailbox, message, and cursor IDs as opaque adapter values. Do
  not expose or reconstruct raw account authorities or full mailbox URLs.
- Keep metadata queries bounded: default 50, maximum 200, cursor pagination,
  bound parameters, and the implementation deadline. Do not read bodies during
  `GET /mail/accounts`, `GET /mail/mailboxes`, or `GET /mail/query`.
- Use `GET /mail/get` for one opaque message ID. It defaults to metadata; body text
  requires `"content":"text"` in params, and raw RFC 822 requires
  `"content":"raw"` plus an `output` path in params.
  Never put raw bytes in JSON or overwrite an existing output file.
- Preserve `partial`, `metadata_only`, `incomplete`, and `fallbackReason` exactly;
  do not present missing or partial cache content as a complete empty message.
- Missing cached text may fall back to Mail.app only for explicit
  `"content":"text"` in params.
  Ordinary fallback must not launch Mail.app; raw RFC 822 never falls back because
  AppleScript text cannot provide a byte-exact replacement.
- When SQLite is unavailable, Mail.app metadata fallback requires Mail to be
  running and Automation to be authorized. It is limited to 32 accounts, 200
  top-level mailboxes, 25 message candidates, and five seconds. Preserve its
  `incomplete`, no-cursor, fallback-reason, and limitation fields; never treat a
  no-match response as complete. Its `ambx_`/`appmsg_` IDs are backend-specific.
- `POST /mail/reveal` is an explicit visible operation that may launch and activate
  Mail.app. Do not use it as a hidden read path or claim it verifies content bytes.
- `OPTIONS /mail/attachments/verify` is metadata-only validation. It may compare SQLite
  row counts with cached MIME part counts, but it must not return attachment names,
  paths, or payloads. Partial EMLX is always unverified, even when counts agree.
- Serialize Apple Events, keep the 3-second timeout and 30-second timeout circuit
  breaker, and preserve the stable Automation error categories.
- Do not render HTML with WebKit or load remote resources. The text projection
  uses bounded MIME decoding and a local HTML-to-text sanitizer.
- On the verified macOS 26.4 V10 store, `mailboxes.source` is null; account scope
  is intentionally derived from the mailbox URL scheme and authority and then
  hash-redacted. Re-probe schema behavior on every new store version.
- Use `scripts/run_mail_doctor_smoke.sh --require-fast-path` for the full
  consistency gate and `scripts/run_mail_metadata_smoke.sh` for privacy-safe
  live command validation. `scripts/run_mail_content_smoke.sh` stores one text
  and raw sample only in an auto-deleted temporary directory and prints no
  content. `scripts/run_mail_attachment_smoke.sh` prints aggregate counts only.
  None of the smoke tests writes to Mail's store.
- Use `scripts/run_mail_automation_smoke.sh --gui-session` when an agent shell is
  outside the loginwindow bootstrap namespace. It verifies Automation and one
  visible reveal without printing message fields. Add `--with-text-fallback`
  only when reading one uncached body is explicitly acceptable.
- `scripts/run_mail_app_metadata_smoke.sh` forces the bounded metadata backend
  only for development verification. It stores JSON in an auto-deleted private
  temp directory and prints aggregate counts only.

## Non-negotiable Calendar rules

- Calendar reads require EventKit full access. Write-only access is not readable.
- Default and explicit Calendar operations accept only the uniquely verified
  iCloud CalDAV source; never fall back to Local, Exchange, Google, or another source.
- Treat source IDs, calendar IDs, `calevent_` IDs, and cursors as local opaque values.
  A `calevent_` ID binds a calendar item and occurrence start so recurring events
  do not silently resolve to the first occurrence.
- Calendar query requires an explicit bounded date range: start before end and at
  most 366 days. Default limit is 50 and maximum is 200.
- Calendar create/edit/delete requires `--dry-run` or `--apply`. Delete apply also
  requires `--confirm "DELETE EVENT"`.
- Recurring edit/delete requires `"span":"this"` or `"span":"future"` in
  params; never infer a
  series scope.
- Attendees are readable but read-only in 0.3. Do not claim invitations can be sent.
- All-day event JSON uses `YYYY-MM-DD` and an exclusive end date. Timed events use
  ISO 8601 timestamps with offsets. Do not interchange the two forms.
- Alarm writes use exactly one of `relativeMinutes` or `absoluteDate`; `alarms: []`
  clears reminders. Create must remove EventKit-inherited default alarms first.
- `POST /calendar/create` with `"idempotent":true` in params uses a
  privacy-minimized 60-second local receipt because
  separate EventKit processes are not immediately consistent. Receipts must never
  store event titles, notes, locations, attendees, or other event content.
- `GET /calendar/conflicts` scans at most 200 events and treats adjacent boundaries as
  non-conflicting. Narrow the range when the hard cap is exceeded.
- Do not use an existing user event as an apply fixture. Real CRUD verification
  must create and clean up one disposable event after explicit authorization.
- The only documented real-write gate is
  `run_local_calendar_integration.sh --with-writes --confirm "CALENDAR CRUD TEST"`.
  The confirmation argument does not replace the user's explicit authorization
  to run it in the current task.
- The recurring-event write gate is
  `run_calendar_recurrence_integration.sh --confirm "CALENDAR RECURRENCE TEST"` and
  also requires explicit current-task authorization. It must finish with zero URL fixtures.
- The all-day/alarm/conflict write gate is
  `run_calendar_feature_integration.sh --confirm "CALENDAR FEATURE TEST"` and
  also requires explicit current-task authorization. It verifies date-only
  read-back, relative/absolute/cleared alarms, strict overlap versus adjacent
  boundaries, and zero remaining URL fixtures.
- `run_calendar_read_smoke.sh` and `run_calendar_dry_run_smoke.sh` print aggregate
  status only and auto-delete private temporary JSON.
- The default dry-run smoke must not select an arbitrary user event for edit or
  delete preview. Those paths use separately authorized disposable-event gates;
  a recurring occurrence may legitimately receive a new opaque ID in preview.

## Non-negotiable Reminders rules

- Reminders access requires EventKit full access and targets only the uniquely
  verified iCloud CalDAV source; never fall back to Local, Exchange, or Google.
- Treat source/list/`reminder_` IDs and cursors as opaque local values. Reminders
  0.4 does not define a custom external ID.
- `create --dry-run` resolves only a writable list in the selected iCloud source,
  returns an ID-less draft, and never calls `EKEventStore.save`.
- `create --apply` saves exactly once and returns an opaque reminder ID. It must
  distinguish `readback_confirmed` from `save_accepted_readback_pending`; the
  latter is not a retry signal and must direct the caller to use `get`.
- Optional `POST /reminders/create` with `"idempotent":true` in params uses a
  private 60-second local receipt. The
  receipt may contain only a SHA-256 input fingerprint, opaque reminder/list
  IDs, and timestamp metadata; it must never contain reminder content.
- `resources` reports Reminders as writable because guarded create apply exists;
  this does not imply every future Reminders mutation or list-management feature exists.
- Unknown top-level create fields fail closed. Date-only, floating-time, IANA-time,
  alarm, and recurrence validation must run before constructing a draft.
- Location alarms are readable but not writable. Do not silently drop or convert them.
- `edit` is a partial patch: omitted fields are preserved, `null` clears only
  nullable fields, and a value replaces the field. `title`, `priority`, and
  `listID` cannot be null; completion state is reserved for complete/reopen.
- Editing `alarms` on a reminder that already contains a location alarm must
  fail rather than silently removing that read-only alarm.
- Edit apply saves exactly once and uses the same read-back-confirmed versus
  save-accepted/read-back-pending no-auto-retry contract as create.
- `complete` sets `isCompleted` and an explicit completion date; `reopen` clears
  both. Repeating either target state is a safe no-op and must not save again.
- A completed recurring reminder may expose its next incomplete occurrence on
  read-back; return it separately as `nextOccurrence` rather than pretending the
  completed occurrence stayed current.
- Recurring completion real-write verification uses only
  `scripts/run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"`
  after explicit current-task authorization. It must verify occurrence advance
  and delete every disposable series item before reporting zero residue.
- Use `scripts/run_reminders_read_smoke.sh` for privacy-minimized reads and
  `scripts/run_reminders_dry_run_smoke.sh` for create preview. The latter must
  verify no reminder was created and must never invoke `--apply`.
- Do not use a user's existing reminder as an apply fixture. Real create/delete
  verification must use one explicitly authorized disposable reminder and
  finish by proving it absent. The only write gate is
  `scripts/run_local_reminders_integration.sh --with-writes --confirm "REMINDERS CRUD TEST"`;
  its confirmation argument does not replace explicit current-task authorization.

## Non-negotiable Photos rules

- Use public PhotoKit only. Never read Photos databases, library packages,
  caches, or private frameworks and never automate Photos.app coordinates.
- `OPTIONS /photos/permission` is status-only by default. Only explicit params
  `{"request":true}` may request read/write authorization.
- Treat limited access as readable but incomplete. Preserve `complete: false`;
  never interpret an empty limited result as an empty full library.
- Treat asset, album, and cursor IDs as opaque local adapter values. Album names
  are not selectors because duplicate titles are valid.
- Metadata query/get must not request image/video bytes or trigger iCloud
  downloads. Exact location is opt-in only.
- Export defaults to no network, refuses overwrite, writes no binary to JSON or
  stdout, and must distinguish originals from paired/adjusted/rendered resources.
- Use `scripts/run_photos_export_smoke.sh` for the live export gate. It may only
  write inside its private temporary directory and must remove output on exit.
  Never add `--allow-network` unless the user explicitly approves downloading a
  selected iCloud-backed resource for that gate.
- Do not expose Photos mutation until each command has dry-run/apply semantics
  and a disposable imported-fixture cleanup gate. Existing personal assets are
  never mutation fixtures.
- Do not log asset filenames, locations, local identifiers, album names, output
  paths, or media bytes. Live smoke tests print aggregate state only.
- Use `scripts/run_photos_read_smoke.sh` for the live album gate. It prints only
  authorization, aggregate kind counts, completeness, and truncation; it must
  stop before collection fetch when access is unreadable.
- Agent sandboxes can become the TCC responsible process. For the real local
  gate, use a stable installed bundle and set `MPIA_APP`; the smoke script
  will launch it through LaunchServices. Do not treat a direct sandbox denial as
  evidence about the app bundle's Photos permission.
- Use `scripts/run_photos_metadata_smoke.sh` for bounded query/get verification.
  It queries at most five recent assets, uses one opaque ID internally for get,
  and prints counts/schema state only. Never print asset IDs, dates, filenames,
  albums, locations, or media bytes.
- Preserve `com.apple.security.personal-information.photos-library` in the
  signed app. Verify the signed entitlement itself. For ad-hoc development,
  install without extended attributes at a stable path and re-sign there;
  iCloud-workspace resource forks and changing code hashes invalidate TCC or
  strict code-signing evidence.

## Non-negotiable Notes rules

- Notes 0.6 uses the public Notes.app scripting dictionary through Apple Events;
  do not call it a native Notes Framework adapter.
- Never inspect Notes databases, caches, private frameworks, or Notes-owned
  CloudKit containers, and never automate Notes.app by GUI coordinates.
- `OPTIONS /notes/permission` is status-only by default. Only explicit params
  `{"request":true}` may request Automation consent.
- The default future query path is metadata-only. Note plaintext/HTML body must
  require an explicit get projection, use a byte cap, and never enter logs.
- Treat account, folder, note, attachment, and cursor IDs as adapter-owned opaque
  values. Do not expose raw Notes scripting IDs in the JSON contract.
- Every Apple Event operation must be bounded by object count and deadline;
  never fetch body for `every note` and use a timeout circuit breaker.
- Real write verification may use only a disposable test note with explicit
  authorization and proven zero-residue cleanup. Existing notes are never
  mutation fixtures.
- Notes writes require a valid local user-confirmed iCloud write-account binding,
  an explicit non-shared opaque folder, dry-run/apply, and immediate read-back.
- Supply create/rename/move JSON through the REST `--body` object. This deliberate
  0.9.3 tradeoff can expose values to shell history/process inspection; never use
  it for secrets, and never copy body content into diagnostics, receipts, or logs.
- Never automatically retry `save_accepted_readback_pending` or `outcome_unknown`.
- Released 0.6.1 does not support existing-body replacement. The 0.6.2
  `PUT /notes/edit-body` route is limited to simple, attachment-free content and
  additionally requires the exact current plaintext SHA-256. Its disposable
  signed-app apply/read-back/cleanup gate is recorded as passed.
- The 0.6.2 folder create/rename and move-preview commands require strict
  stdin/file JSON and opaque selectors. JSON null explicitly selects the bound
  account root. Rename/move require the exact current folder-name SHA-256, and
  move also requires the exact current parent ID or null. Never infer a folder
  from its name.
- Reject default/shared folders, duplicate sibling names, cycles, incomplete
  folder graphs, and cross-account moves. A safe no-op must not send a write
  Apple Event. Folder names must never enter result JSON, diagnostics, receipts,
  or integration logs.
- Never apply folder move through Notes 4.13 scripting. Runtime evidence showed
  identity loss and a temporarily invalid metadata graph; apply must return
  `NOTES_FOLDER_MOVE_UNSUPPORTED` without sending a write Apple Event.
- Empty-folder deletion preview in the 0.6.2 path must require the exact
  current name SHA-256 and explicit parent ID or null. Reject default/shared,
  non-empty, recursive, stale, incomplete-graph, and cross-account targets.
  Runtime testing showed metadata invalidation and iCloud resurrection under a
  new opaque ID. Apply must return `NOTES_FOLDER_DELETE_UNSUPPORTED` before any
  write Apple Event and must not be retried automatically.
- The 0.6.2 single-note delete path is recoverable soft deletion only.
  It requires the latest modification date, exact `DELETE NOTE` confirmation,
  a fresh direct read, and bound-account/non-shared/non-locked scope. Never
  automatically retry pending or unknown outcomes. Permanent deletion and
  emptying Recently Deleted remain UI-only and require action-time confirmation.
- Attachment mutation, shared/locked writes, and cross-account moves remain
  unsupported.

## Non-negotiable Safari rules

- Safari 0.8.1 may read only the bounded public-user `Bookmarks.plist` snapshot.
  Reject symlinks, oversized files, malformed roots, duplicate Reading List
  proxies, excessive depth/node counts, and unknown unsafe structures.
- Bookmark, folder, Reading List, and cursor IDs are adapter-owned opaque values.
  A cursor is bound to the exact plist SHA-256 and must fail stale after any
  snapshot change.
- Never return or log Safari raw plist IDs, plist contents, titles, URLs,
  previews, paths, or AppleScript source. Live smoke output is aggregate or
  opaque only.
- Reading List add uses Safari's official AppleScript command with strict JSON,
  `--dry-run|--apply`, a five-second deadline, normalized-URL idempotency, and
  immediate bounded read-back.
- Pending or unknown Reading List outcomes prohibit automatic retry. The Agent
  must query the normalized URL after Safari has had time to save.
- Version 0.8.1 exposes guarded local-only bookmark/folder CRUD. Apply requires
  Safari fully exited, the exact dry-run source hash, private recovery, metadata
  and unknown-field preservation, atomic replacement, and bounded local
  read-back. Every result must say `syncStatus=local_only`; never claim that a
  successful local write reached iCloud. Never stop or edit iCloud
  synchronization processes.
- A copied binary plist need not be byte-identical after Foundation
  serialization. Verify typed canonical hashes for every untouched subtree,
  preserve every source xattr value, and report destination-only
  `com.apple.provenance`; any other added xattr fails closed. Copy-only evidence
  is not authorization to replace the live plist.
- The 0.8.1 quiescence gate must reject a running Safari app and any exact-plist
  `lsof` holder, compare two full snapshots at least 500 ms apart, create only
  mode-0600 recovery/metadata files in a mode-0700 directory, and compare a third
  snapshot after backup. Use bounded non-mapped reads so the gate does not hold
  the plist itself. A prior gate report cannot authorize a later replacement.
- A direct-plist candidate must be on the same volume and use `RENAME_SWAP`, not
  overwrite-in-place. Keep the exact old file until candidate, old side,
  recovery, parser, metadata, and caller read-back all pass; otherwise swap back
  and verify the restored source. Reapply and hash every source xattr after
  writing candidate data because macOS may mutate quarantine metadata.
- The 0.8.1 live fixture gate additionally requires the exact phrase
  `CREATE SAFARI 0.8.1 FIXTURE`. Retain raw cleanup identifiers only in the
  mode-0600 recovery receipt, launch Safari for immediate UI/parser read-back,
  and never retry the live replacement automatically.
- The attended 0.8.1 live experiment proved one local bookmark addition and no
  loss of ordinary bookmarks. The simultaneous Reading List deletion was a
  separate user action. A second iCloud device did not receive the fixture, so
  direct-plist writes are local-only and must never imply iCloud synchronization.
  Do not restart the private `SafariBookmarksSyncAgent` as a sync trigger.
  A sync-capable path must use a separately gated Safari-owned mutation or
  import and second-device read-back. Research-only capability detection may
  inspect the unsupported Safari private `BookmarksController` selectors, but
  it must not mutate data or become a public CLI contract. Any private-framework
  fixture requires separate explicit authorization, disposable data, and a
  second-device gate; failure must fall back to Safari-owned import/UI rather
  than daemon manipulation.
- Real Reading List add or direct-plist gates require explicit current-task
  authorization and zero-residue cleanup. Existing personal Safari data is
  never a mutation fixture.

## Non-negotiable Messages rules

- Messages 0.9.1 is read-only. It reads `~/Library/Messages/chat.db` through a
  fail-closed SQLite fast path; never write the database, WAL/SHM sidecars, or
  Messages account configuration.
- `OPTIONS /messages/permission` is status-only and must not prompt. It accepts
  no consent-request parameter. Reading requires Full Disk Access for the responsible process.
- Run a runtime schema fingerprint and a bounded structural gate before any
  query; an unknown schema is fail-closed and must not be guessed.
- `GET /messages/recent` is newest-first, cursor-paginated, default 50 / max 200,
  with a query deadline. Its `service` param accepts `imessage` or `sms`.
- Never return or log raw `ROWID`, `guid`, `chat_identifier`, participant
  handles, phone numbers, emails, or attachment paths. Only opaque `msg_` /
  `chat_` / `cur_` tokens cross the contract.
- Body text is a projection truncated to a hard 500-char cap; the response marks
  `truncated` when the cap is hit.
- No send/reply, mark-read, reaction, attachment export, or any write in 0.9.1.
- Live smoke output is aggregate-only (counts, truncation, completeness); it
  must never print bodies, handles, or identifiers. Use
  `scripts/run_messages_read_smoke.sh`, which stops before any query when Full
  Disk Access is unavailable.

## Non-negotiable Phone rules

- Phone 0.9.2 is read-only. It reads
  `~/Library/Application Support/CallHistoryDB/CallHistory.storedata` (a Core
  Data SQLite store in WAL mode) through a fail-closed SQLite fast path; never
  write the store or its WAL/SHM sidecars.
- `OPTIONS /phone-calls/permission` is status-only and must not prompt. It accepts
  no consent-request parameter. Reading requires Full Disk Access for the responsible process.
- Run a runtime schema fingerprint and a bounded structural gate (required
  `ZCALLRECORD` columns) before any query; an unknown schema is fail-closed.
- `GET /phone-calls/recent` is newest-first, cursor-paginated, default 50 / max 200,
  with a query deadline. `ZDATE` is Apple-epoch **seconds** (not nanoseconds);
  `ZORIGINATED` is direction (0=incoming, 1=outgoing); incoming +
  `ZANSWERED=0` is missed; outgoing "connected" is derived from `ZDURATION>0`.
- Never return or log counterparty numbers, emails, names, locations, carriers,
  `ZADDRESS`, `ZNAME`, `ZUNIQUE_ID`, or `ZHANDLE.ZVALUE`/`ZNORMALIZEDVALUE`.
  Only opaque `call_` / `cur_` tokens cross the contract.
- No placing calls, deleting history, marking read, voicemail, or any write.
- Live smoke output is aggregate-only (counts, truncation, completeness); it
  must never print counterparty identifiers. Use
  `scripts/run_phone_calls_read_smoke.sh`, which stops before any query when
  Full Disk Access is unavailable.

## Local verification

These checks are local-only and do not require CI:

```bash
bash scripts/run_swift_tests.sh
swift build
bash scripts/run_cli_contract_tests.sh
bash scripts/run_mail_doctor_smoke.sh --require-fast-path
bash scripts/run_mail_metadata_smoke.sh
bash scripts/run_mail_content_smoke.sh
bash scripts/run_mail_attachment_smoke.sh
bash scripts/run_mail_app_metadata_smoke.sh
bash scripts/run_mail_automation_smoke.sh --gui-session
bash scripts/run_mail_release_gate.sh
bash scripts/run_release_gate.sh
bash scripts/run_calendar_contract_tests.sh
bash scripts/run_calendar_read_smoke.sh
bash scripts/run_calendar_dry_run_smoke.sh
bash scripts/run_photos_read_smoke.sh
bash scripts/run_photos_metadata_smoke.sh
bash scripts/run_photos_export_smoke.sh
bash scripts/run_notes_write_integration.sh
bash scripts/run_notes_folder_integration.sh
bash scripts/run_shortcuts_authoring_smoke.sh
bash scripts/run_safari_read_smoke.sh
bash scripts/run_safari_dry_run_smoke.sh
bash scripts/run_messages_read_smoke.sh
bash scripts/run_phone_calls_read_smoke.sh
# Add --apply only for an explicitly authorized disposable signed-app gate.
bash scripts/run_local_calendar_integration.sh
bash scripts/run_installed_release_smoke.sh
bash scripts/check_public_release_prerequisites.sh
```

The ordinary `run_release_gate.sh` must call `run_cli_contract_tests.sh --no-apply`.
Do not put any real Contacts or Calendar apply fixture in the default release gate.

Use `scripts/run_swift_tests.sh` for the standard local Swift suite. It keeps
XCTest products in a local scratch directory because Xcode 27 can attach iCloud
File Provider/Finder metadata to test bundles built inside this synced checkout,
which causes ad-hoc codesign to reject otherwise valid generated products.

Use `scripts/run_mail_release_gate.sh --with-automation` only for an attended
check: it performs a visible reveal and intentionally fails without retry when
Mail.app exceeds the 3-second Apple Event budget.

Run `scripts/run_installed_release_smoke.sh` only after installing the Release
binary. It verifies the installed version and V10 SQLite path without printing
mail fields.

Before any external release action, run
`scripts/check_public_release_prerequisites.sh`. Treat a missing Developer ID,
notary profile, valid GitHub login, or clean worktree as a hard stop; the script
does not authorize committing, tagging, pushing, or publishing.

The contract script uses the raw Debug executable and therefore requires the
calling process to have Contacts permission. For this machine's TCC behavior,
real read verification must use the authorized `.build/debug/mpia.app`;
see `docs/development/local-debug-and-tcc_CN.md`.

Real Contacts writes are exceptional operations and must follow the documented
fixture and explicit-authorization workflow in `docs/development/rules.md`.
