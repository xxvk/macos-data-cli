# Usage

`mpia` is a local Terminal CLI. It uses Apple public frameworks and
explicitly documented app Automation interfaces; agents do not need a special
integration.

## Unified resources

List the currently discoverable Contacts, Mail, Calendar, Reminders, Photos,
Notes, Shortcuts, Safari, Messages, and Call History resource scopes in one
machine-readable response:

```text
mpia resources --format json
```

Each resource reports an adapter-owned opaque `id`, `kind`, `provider`,
`displayName`, and capabilities (`readable`, `writable`, `selected`, and
`permission`). Contacts selection reflects the verified iCloud container.
Mail account scopes are intentionally not selected merely because one account
exists; the preferred `aim-tech.jp` work account still requires explicit,
privacy-safe verification. With full access, Calendar reports EventKit sources
and selects only the uniquely verified iCloud CalDAV source. Reminders follows
the same fail-closed iCloud source policy and reports a distinct
`remindersSource` resource kind.
Photos always reports one `photosLibrary` scope. Before authorization it is not
readable; limited access is readable with permission `limited` but represents an
incomplete library view.
Notes reports one read-only `notesLibrary` scope. Its permission reflects the
responsible process's Notes.app Automation state and does not imply access to a
private Notes database.
Safari reports one `safariLibrary` scope. Readability means the responsible
process can read `Bookmarks.plist`; writability covers guarded local-only plist
mutation or the Automation-backed Reading List add path. It does not imply
iCloud synchronization, and local bookmark writes require Safari fully quit.
Messages reports one read-only `messagesLibrary` scope and Call History reports
one read-only `phoneLibrary` scope; readability for both requires Full Disk
Access and is never writable. Neither exposes counterparty identifiers.

## Messages (0.9.1)

Read-only recent messages from the local Messages SQLite store
(`~/Library/Messages/chat.db`). Requires Full Disk Access for the responsible
process; `messages permission` is a status-only probe and never prompts.

```text
mpia messages permission --format json
mpia messages recent --limit 50 --format json
mpia messages recent --limit 20 --service imessage --format json
mpia messages recent --limit 20 --cursor <opaque-cursor> --format json
```

`messages recent` returns newest-first, cursor-paginated metadata (`id`,
`service`, `isFromMe`, `sentAt`, `conversationId`) plus a bounded, redacted
plain-text projection (`text`, truncated to 500 chars). Participant handles,
raw local IDs, and account identifiers are never returned. Read-only only: no
send/reply, mark-read, attachment export, or any write.

## Phone calls (0.9.2)

Read-only recent call history from the local Call History Core Data SQLite store
(`~/Library/Application Support/CallHistoryDB/CallHistory.storedata`). Requires
Full Disk Access for the responsible process; `phone-calls permission` is a
status-only probe and never prompts.

```text
mpia phone-calls permission --format json
mpia phone-calls recent --limit 50 --format json
mpia phone-calls recent --limit 20 --cursor <opaque-cursor> --format json
```

`phone-calls recent` returns newest-first, cursor-paginated metadata (`id`,
`direction`, `kind`, `answered`, `missed`, `durationSeconds`, `at`). Counterparty
numbers, names, locations, carriers, and raw local IDs are never returned.
Read-only only: no placing calls, deleting history, or any write.

## Safari (0.8.1)

Safari bookmarks and Reading List share one bounded, read-only property-list
snapshot. Reads may require Full Disk Access for the stable app or Terminal host.
Permission status never prompts unless `--request` is explicit:

```bash
mpia safari permission --format json
mpia safari permission --request --format json
```

Ordinary bookmark commands exclude Safari proxy nodes and the Reading List
subtree. Folder relationships use opaque IDs. Filters combine with AND semantics;
pages default to 50 and cap at 200. Cursors become stale whenever the underlying
plist changes.

```bash
mpia safari bookmarks list --limit 50 --format json
mpia safari bookmarks query --text "reference" --format json
mpia safari bookmarks query --url "https://example.com" \
  --folder-id <opaque-folder-id> --format json
mpia safari bookmarks get --id <opaque-bookmark-or-folder-id> --format json

mpia safari reading-list list --read false --limit 50 --format json
mpia safari reading-list query --text "article" --format json
mpia safari reading-list get --id <opaque-reading-list-id> --format json
```

Reading List creation accepts strict JSON only. The result does not echo the
URL, title, or preview; it returns a URL SHA-256 and optional opaque read-back ID.

```bash
printf '%s' '{"url":"https://example.com/article","title":"Example"}' \
  | mpia safari reading-list add --stdin --dry-run --format json

printf '%s' '{"url":"https://example.com/article","title":"Example"}' \
  | mpia safari reading-list add --stdin --apply --format json
```

An existing normalized URL is a safe no-op. `save_accepted_readback_pending`
and `SAFARI_READING_LIST_OUTCOME_UNKNOWN` both prohibit automatic retry; query
the original URL after Safari saves. Version 0.8.1 also exposes the separately
guarded local-only bookmark and folder CRUD contract below. See the
[Safari architecture](development/safari-adapter-architecture.md) for its
recovery, atomic-write, read-back, and no-iCloud-sync boundaries.

### Local-only bookmark and folder CRUD

Use `bookmarks create|edit|move|delete` and
`folders create|rename|move|delete`. Input is strict JSON. Dry-run is the
default and returns `sourceSHA256Before`; copy that value into
`expectedSourceSHA256` before `--apply`. Apply fails closed unless Safari is
fully quit and private recovery, atomic swap, and read-back all succeed.

```bash
printf '%s' '{"parentID":"<opaque-folder-id>","index":0,"title":"Example","url":"https://example.com"}' \
  | mpia safari bookmarks create --stdin --format json

printf '%s' '{"id":"<opaque-bookmark-id>","title":"Updated","url":"https://example.com/updated","expectedSourceSHA256":"<dry-run-source-hash>"}' \
  | mpia safari bookmarks edit --stdin --apply --format json

printf '%s' '{"id":"<opaque-bookmark-id>","expectedSourceSHA256":"<dry-run-source-hash>"}' \
  | mpia safari bookmarks delete --stdin --apply \
      --confirm "DELETE SAFARI BOOKMARK" --format json
```

Folder deletion uses `DELETE SAFARI FOLDER` and only accepts an empty folder.
Results always report `syncStatus=local_only`; agents must not interpret a
successful local read-back as iCloud synchronization.

## Shortcuts (0.7.0–0.7.2)

The base 0.7.0 adapter uses the system `shortcuts` CLI and public `Shortcuts Events`
scripting dictionary. Names are display-only and every selection uses an opaque
ID. The public interface exposes action count, not the action graph or parameters.
`Shortcuts Events` is an on-demand helper and may be absent while idle. Read and
write commands start it without activating the Shortcuts UI before sending their
bounded Apple Event; an actual launch or connection failure remains a structured
error. The standalone permission probe may still report `targetNotRunning` while
the helper is idle.

```bash
mpia shortcuts permission --format json
mpia shortcuts permission --request --format json
mpia shortcuts list --limit 50 --format json
mpia shortcuts folders --limit 50 --format json
mpia shortcuts get --id <opaque-shortcut-id> --format json
mpia shortcuts list --folder-id <opaque-folder-id> --limit 50 --format json
```

Move defaults to preview. Apply requires the exact phrase and reads the folder ID
back within the bounded Apple Event:

```bash
mpia shortcuts move --id <opaque-shortcut-id> \
  --destination-folder-id <opaque-folder-id> --dry-run --format json

mpia shortcuts move --id <opaque-shortcut-id> \
  --destination-folder-id <opaque-folder-id> \
  --apply --confirm "MOVE SHORTCUT" --format json
```

Running a shortcut can cause arbitrary external side effects, so it requires
explicit apply and confirmation. At most 16 input files are accepted and the
deadline is 1...300 seconds. Inline output defaults to UTF-8 text capped at
256 KiB; binary or larger output requires a nonexistent `--output-path`, and
overwrite is refused. A timeout means side effects may already have happened;
Agents must not retry automatically.
Plaintext results are emitted by Apple's CLI on stdout, so mpia captures
stdout privately, applies the size/UTF-8/hash checks, and only then returns JSON
or atomically writes the requested output file.

```bash
mpia shortcuts run --id <opaque-shortcut-id> \
  --input-path ./input.txt --output-type public.utf8-plain-text --timeout 30 \
  --apply --confirm "RUN SHORTCUT" --format json
```

Version 0.7.1 added guarded Cherri managed-source validation, build, create,
update, and local
registry lifecycle commands:

```bash
mpia shortcuts author validate --source ./managed.cherri --format json
mpia shortcuts author build --source ./managed.cherri \
  --output ./managed.shortcut --signing-mode people-who-know-me --format json
mpia shortcuts create --source ./managed.cherri --idempotent --dry-run --format json
mpia shortcuts create --source ./managed.cherri --idempotent --apply \
  --confirm "CREATE MANAGED SHORTCUT" --format json
mpia shortcuts update --id <managed-opaque-id> --source ./managed-v2.cherri \
  --expected-source-sha256 <sha256> --strategy replace --dry-run --format json
mpia shortcuts managed list --format json
```

These commands require optional Cherri 2.3.x, never use remote signing, refuse
output overwrite, and return hashes/byte counts rather than source or action
parameters. Validate/build never import or run an artifact. Create/update are
preview by default; apply opens a visible Shortcuts.app import and writes the
private registry only after metadata read-back. Update is managed-ID-only and
requires the current source hash. Pending/unknown outcomes prohibit automatic
retry. See [`shortcuts-authoring.md`](development/shortcuts-authoring.md) for
the source allowlist, exact confirmations, and replace/retain-old behavior. The
macOS 27 Beta 5 live gate passed with exact black-box output and zero residue;
public observed action counts remained `0`, so they are reported separately
from compiled counts and cannot prove the action graph. Experimental editing of arbitrary existing shortcuts
starts with read-only local acquisition classification and planning:

```bash
mpia shortcuts edit inspect --input ./candidate.shortcut --format json
mpia shortcuts edit inspect --input ./candidate.cherri --format json
mpia shortcuts edit plan --input ./candidate.shortcut --patch ./plan.json --format json
# or: ... --stdin --format json
mpia shortcuts edit copy --input ./candidate.shortcut --patch ./plan.json \
  --expected-editor-name-sha256 <sha256> --dry-run --format json
mpia shortcuts edit copy --input ./candidate.shortcut --patch ./plan.json \
  --expected-editor-name-sha256 <sha256> --apply \
  --confirm "EDIT SHORTCUT COPY" --format json
mpia shortcuts edit ui-inspect --format json
```

The input must be one non-symlink local regular file no larger than 10 MiB.
URI syntax, including iCloud share links, is rejected before any file read. The
command has no network request, redirect, clipboard-read, download, or import path.
Results contain only SHA-256, byte count, format, bounded counts, risk flags,
capability, and stable reason codes. They never contain path, Shortcut name,
source, action identifiers, parameters, or embedded values. A valid `.cherri`
uses `managed_source_route`; a narrowly allowlisted unsigned artifact may be a
`semantic_edit_candidate`. Opaque/signed files, unknown actions, nested magic
variables or attachments, suspected secrets, device-bound references, and
unbounded structures return `manual_migration_required`. A plan reports
`canApplySemanticEdit=true` only when every operation is `replace_text`, when
every operation is append-only `insert_text` and the graph already contains a
Text action, or when every operation is `delete_action` and at least one action
remains, or when every operation is a bounded `move_action`. This is copy-first
capability, not permission to edit the original. No version may
mutate Shortcuts SQLite, CloudKit, or private-framework data directly.

An edit-plan document is strict JSON. It requires the exact lower-case
`expectedInputSHA256` returned by inspect and 1...64 sequential operations:

```json
{
  "expectedInputSHA256": "<64-lowercase-hex>",
  "operations": [
    {"operation":"insert_text","index":1,"value":"new text"},
    {"operation":"replace_text","index":0,"value":"replacement"},
    {"operation":"move_action","fromIndex":1,"toIndex":0},
    {"operation":"delete_action","index":1}
  ]
}
```

Indexes refer only to visible non-output actions and each operation observes the
graph produced by the preceding operation. Text values are capped at 64 KiB;
the whole patch is capped at 256 KiB. The result contains value byte counts and
SHA-256 only, never the values themselves. Replacement currently targets text
actions only, deletion cannot empty the graph, and a move must change index.
Equal adjacent semantic actions are rejected because the reordered state cannot
be proven. The terminal output action is never editable. This command is not a dry-run alias for a hidden write:
there is no `--apply` path and no Accessibility or Apple Event is sent.

`edit copy --dry-run` validates the same artifact and patch but never constructs
the system AX bridge. Apply additionally requires the SHA-256 of the exact
visible Shortcut editor name (UTF-8 bytes, no newline) and the confirmation
phrase above. It duplicates the editor, verifies a graph-identical copy, changes
only calibrated Text fields, and reads back after every operation. Append-only
insert invokes exact `duplicateAction:` on an existing Text action and changes
only the appended value; its index must equal the current action count. Delete
presses only the exact resolver-bound Close button and waits for the expected
smaller graph. All-move plans invoke only exact reorder menu identifiers and
read back complete visual order after each adjacent step. A graph without Text,
middle insertion, same-index/equal-neighbor moves, and mixed-operation plans
remain unsupported. Pending or unknown outcomes
must not be retried automatically.

`ui-inspect` is a separate read-only Accessibility capability probe. It never
requests consent, launches or activates Shortcuts.app, and has no click, key,
set-value, or other AX action path. The tree is capped at 2,000 nodes and depth
32. A candidate requires semantic editor marker plus toolbar/group/scroll-area
hierarchy; generic roles alone are rejected. Results expose only permission,
target/bounds status and counts—never window titles, labels, identifiers, or
other UI values. Multiple candidates return `ambiguous`; every status keeps
`canApplySemanticEdit` false.

`inspect`, `plan`, and `ui-inspect` remain read-only. The public mutation surface
is limited to the guarded `edit copy` replace-text, append-only insert, and
bounded all-delete routes
described above.

## Notes (0.6 read-only development slice)

Inspect Notes.app Automation status without prompting:

```text
mpia notes permission --format json
```

Only an explicit request may ask macOS for consent:

```text
mpia notes permission --request --format json
```

The response contains `access`, `readable`, `complete`, and `requested`.
Possible access states are `available`, `denied`, `requiresConsent`,
`targetNotRunning`, `targetUnavailable`, and `unknown`.

Discover bounded account and nested-folder structure without reading note titles
or bodies:

```text
mpia notes accounts --format json
mpia notes folders [--account-id <opaque-id>] [--parent-id <opaque-id>] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
```

Account and folder IDs are SHA-256-derived adapter-owned selectors; raw Notes
scripting IDs are not returned. Folder cursors are bound to the account/parent
filter and stale or cross-filter reuse fails closed.

Query bounded note metadata without reading note bodies:

```text
mpia notes query [--account-id <opaque-id>] [--folder-id <opaque-id>] \
  [--title <substring>] [--modified-after <iso8601>] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
```

Results contain only adapter-owned note/account/folder IDs, title, creation and
modification dates, and password-protected/shared flags. They do not contain
plaintext, HTML, attachments, or raw Notes scripting IDs. Query cursors are
bound to all filters and fail closed when reused with a different filter.
Enumeration is capped at 32 accounts, 200 folders, 200 notes, depth 16, and a
five-second Apple Events deadline; overall process launch time may be longer.
`complete: false` means the bounded snapshot cannot prove that all matching
notes were examined. The adapter uses the Notes.app scripting dictionary and
never reads private Notes stores or CloudKit containers. See the
[Notes 0.6 feasibility decision](development/notes-adapter-feasibility.md).

Read one selected note. Metadata is the default and does not fetch a body:

```text
mpia notes get --id <opaque-note-id> --format json
mpia notes get --id <opaque-note-id> --body plaintext --format json
mpia notes get --id <opaque-note-id> --body html --format json
mpia notes get --id <opaque-note-id> --include-attachments --format json
```

`plaintext` and `html` are explicit sensitive-data opt-ins. Returned UTF-8 body
data is capped at 256 KiB; larger and password-protected notes fail closed. The
one-note Apple Event is deadline-bounded, but Notes supplies the property before
the CLI can enforce its UTF-8 response cap, so this is an output boundary rather
than a strict Apple Events peak-memory guarantee. Body content is never written
to diagnostic logs.

Attachment metadata is also explicit. It returns at most 100 adapter-owned
opaque attachment IDs plus name, creation/modification dates, content
identifier, URL, and shared state. It never reads attachment `contents`, saves,
or exports binary data. `attachmentsComplete: false` means the per-note cap was
reached. Binary export remains deferred behind its own destination, byte-limit,
no-overwrite, and cleanup gate.

### Guarded Notes writes

Writes are disabled until the user binds one opaque account ID as the local
iCloud write account. This is a user attestation because the Notes scripting
dictionary exposes no stable account-type field:

```text
mpia notes write-account status --format json
mpia notes write-account bind --account-id <notesaccount-id> --dry-run --format json
mpia notes write-account bind --account-id <notesaccount-id> --apply \
  --confirm "BIND ICLOUD NOTES" --format json
```

The private binding contains no account name or raw scripting ID. Every write
revalidates it and requires an explicit non-shared folder in that account.

Create JSON is supplied only through a file or stdin:

```json
{"folderID":"notesfolder_...","title":"Title","bodyFormat":"plaintext","body":"Body"}
```

```text
mpia notes create --stdin --dry-run --format json
mpia notes create --stdin --apply --idempotent --format json
```

Rename and move require the exact ISO-8601 `modificationDate` returned by the
latest query/get:

```text
mpia notes rename --id <note-id> --stdin --dry-run --format json
# stdin: {"title":"New title","expectedModificationDate":"2026-08-14T00:00:00Z"}

mpia notes move --id <note-id> --stdin --apply --format json
# stdin: {"destinationFolderID":"notesfolder_...","expectedModificationDate":"2026-08-14T00:00:00Z"}
```

The in-development recoverable delete requires the latest whole-second
modification date and an exact confirmation phrase:

```text
mpia notes delete --id <note-id> --stdin --dry-run --format json
mpia notes delete --id <note-id> --stdin --apply --confirm "DELETE NOTE" --format json
# stdin: {"expectedModificationDate":"2026-08-14T00:00:00Z"}
```

It only requests Notes soft deletion into Recently Deleted. Permanent deletion
and emptying Recently Deleted are unsupported. A pending or unknown result must
not be retried automatically.

The 0.6.2 body replacement command additionally requires the
SHA-256 of the complete current plaintext returned by `notes get --body
plaintext`. This second precondition detects body drift independently of the
whole-second modification date:

```text
mpia notes edit-body --id <note-id> --stdin --dry-run --format json
# stdin: {"bodyFormat":"plaintext","body":"Replacement body","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"<64-lowercase-hex>"}
```

`edit-body` preserves the existing title by constructing it as the first line,
then replaces the remaining body. It refuses shared/locked notes, any detected
attachment, incomplete attachment inspection, or HTML outside the bounded
simple-text whitelist. It does not promise lossless checklist, table, drawing,
scan, link, or collaboration editing. Dry-run returns old/new hashes and byte
counts without echoing either body; pending and unknown apply results must not
be retried automatically.

The 0.6.2 folder lifecycle commands use strict JSON and opaque
folder IDs. JSON `null` explicitly means the bound account root; omitting a
parent field is an error:

```text
mpia notes folder create --stdin --dry-run --format json
# stdin: {"name":"Projects","parentFolderID":null}

mpia notes folder rename --id <folder-id> --stdin --dry-run --format json
# stdin: {"name":"Archive","expectedNameSHA256":"<64-lowercase-hex>"}

mpia notes folder move --id <folder-id> --stdin --dry-run --format json
# stdin: {"destinationParentFolderID":null,"expectedParentFolderID":"notesfolder_...","expectedNameSHA256":"<64-lowercase-hex>"}

mpia notes folder delete --id <folder-id> --stdin --dry-run --format json
# stdin: {"expectedParentFolderID":null,"expectedNameSHA256":"<64-lowercase-hex>"}

mpia notes folder delete --id <folder-id> --stdin --apply \
  --confirm "DELETE EMPTY NOTES FOLDER" --format json
# apply returns NOTES_FOLDER_DELETE_UNSUPPORTED on Notes 4.13
```

Use `--idempotent` for apply-mode folder creation. Folder rename and move preview use
the current name hash because the public Notes folder dictionary exposes no
modification date; move additionally requires the exact current parent, with
`null` meaning the account root. Operations fail closed for stale hashes or
parents, duplicate sibling names, default/shared folders, cross-account moves,
cycles, or an incomplete bounded folder graph. Safe no-ops do not send a write
Apple Event. Preview, result, diagnostics, and receipts never contain folder
names; they use opaque IDs and SHA-256 values. Pending or unknown outcomes must
not be retried automatically. Notes 4.13 runtime testing showed that its public
folder `move` command cannot preserve and confirm folder identity safely: an
empty nested fixture disappeared from the enumerable graph and metadata became
temporarily invalid. Folder move apply therefore fails closed with
`NOTES_FOLDER_MOVE_UNSUPPORTED`; no write Apple Event is sent.

Folder delete preview never recurses. It accepts only a bound-account,
non-default, non-shared folder whose current name hash and parent still match,
and performs a fresh direct count; any note or child folder returns
`NOTES_FOLDER_NOT_EMPTY`. The real Notes 4.13 apply gate invalidated the metadata
graph and the child later reappeared under a new opaque ID after Notes restarted.
Apply therefore returns `NOTES_FOLDER_DELETE_UNSUPPORTED` before any write Apple
Event. Do not retry it automatically.

No mode means dry-run. Preview/result JSON contains hashes and byte counts, not
title or body content. `save_accepted_readback_pending` and `outcome_unknown`
must never be retried automatically. The `edit-body` command is a released
0.6.2 source capability whose disposable signed-app gate has passed. Folder
create/rename and guarded empty-folder-delete preview are implemented;
the create/rename signed-app gate passed, while move and folder-delete apply are
disabled from runtime evidence. Attachment mutation, note deletion,
shared/locked writes, and cross-account moves are unsupported.

## Photos (0.5 development slice)

Inspect authorization without triggering a prompt:

```text
mpia photos permission --format json
```

Request read/write Photos authorization explicitly:

```text
mpia photos permission --request --format json
```

The response includes `access`, `readable`, `complete`, and `requested`.
`limited` means `readable: true` and `complete: false`. This development slice
can enumerate album metadata after authorization:

```text
mpia photos albums --kind all --limit 50 --format json
mpia photos albums --kind user --limit 50 --cursor <opaque-cursor> --format json
```

Results preserve user folder hierarchy, distinguish user and smart albums, and
allow duplicate titles; use opaque album IDs rather than titles for future
selection. Query bounded asset metadata by creation date, with hidden assets and
exact location excluded by default:

```text
mpia photos query --start 2026-08-01T00:00:00Z --end 2026-08-15T00:00:00Z \
  [--album-id <opaque-album-id>] [--media image|video|audio|unknown] \
  [--favorite true|false] [--include-hidden] [--include-location] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
mpia photos get --id <opaque-asset-id> [--include-location] --format json
```

The range must be ordered and at most 366 days. Query/get return metadata and
opaque references only; they do not call media managers or trigger iCloud media
downloads. `contentAvailability` remains `unknown` in this slice.

Export one explicit resource to a new local file:

```text
mpia photos export --id <opaque-asset-id> --output <file> \
  [--variant original|current|paired-video|adjustment-data] \
  [--allow-network] --format json
```

The default variant is `original`; network access and overwrite are disabled.
If the resource exists only in iCloud, the default command returns
`PHOTOS_CONTENT_NOT_LOCAL` and leaves no partial file. `--allow-network` is an
explicit download opt-in. Multiple same-priority resources return an ambiguity
error instead of guessing. Successful output is staged beside the destination,
moved atomically, and set to mode `0600`. JSON reports only the opaque asset ID,
variant, resource kind, content type, byte count, and whether network was
allowed; it never contains media bytes or echoes the output path. Library
mutation is not implemented yet.
See the [Photos 0.5 architecture](development/photos-adapter-architecture.md).

## Calendar (0.3)

```text
mpia calendar permission --format json
mpia calendar sources --format json
mpia calendar calendars --format json
mpia calendar query --start <iso8601> --end <iso8601> [--calendar <id|unique-title>] [--title <text>] [--limit <1...200>] [--cursor <cursor>] --format json
mpia calendar conflicts --start <iso8601> --end <iso8601> [--calendar <id|unique-title>] --format json
mpia calendar get --id <calevent-id> --format json
mpia calendar create --input event.json --dry-run|--apply [--idempotent] --format json
mpia calendar edit --id <id> --input patch.json --dry-run|--apply [--span this|future] --format json
mpia calendar delete --id <id> --dry-run [--span this|future] --format json
mpia calendar delete --id <id> --apply --confirm "DELETE EVENT" [--span this|future] --format json
```

Reads require EventKit full access; write-only access is insufficient. The
default is the unique iCloud CalDAV source and the adapter never silently falls
back to Local, Exchange, Google, or another account. Query ranges must be ordered
and no longer than 366 days. Results use bounded opaque-cursor pagination.

Dates are ISO 8601 and time zones are IANA identifiers. A minimal create JSON
contains `title`, `startDate`, and `endDate`; `allDay` defaults to false.
Attendees are returned by reads but are not writable in 0.3. Recurrence supports
frequency, interval, weekdays, ordinal weekdays, positional fields, and one end
condition. Recurring edit/delete requires an explicit `this` or `future` span.

Alarms use an `alarms` array. Each item has exactly one of `relativeMinutes`
(negative means before start) or `absoluteDate`; an empty array clears alarms.
Create removes EventKit-inherited default alarms before applying JSON. All-day
events use `YYYY-MM-DD` with an exclusive end date instead of timestamps.

`--idempotent` uses a request fingerprint and a 60-second local receipt to cover
immediate Agent retries. Receipts contain only the fingerprint, opaque event and
calendar IDs, and a timestamp; no title, notes, or location. Edit/delete invalidates
matching receipts. `calendar conflicts` detects strict overlaps across at most 200
events; adjacent events are not conflicts.

The returned `calevent_` ID binds the local calendar item and occurrence start.
Treat it as opaque; moving an event can return a new ID. See the
[Calendar architecture](development/calendar-adapter-architecture.md) for the
full JSON and safety contract.

## Reminders (0.4 development slice)

The current source tree implements permission, iCloud list discovery, bounded
query/get, create, partial edit, complete/reopen, and single-item delete:

```text
mpia reminders permission --format json
mpia reminders sources --format json
mpia reminders lists --format json
mpia reminders query [--status incomplete|completed|all] \
  [--due-start <iso8601>] [--due-end <iso8601>] \
  [--list <id|unique-title>] [--title <text>] \
  [--limit <1...200>] [--cursor <cursor>] --format json
mpia reminders get --id <opaque-reminder-id> --format json
mpia reminders create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
mpia reminders edit --id <opaque-reminder-id> --input <file>|--stdin --dry-run|--apply --format json
mpia reminders complete --id <opaque-reminder-id> --dry-run|--apply --format json
mpia reminders reopen --id <opaque-reminder-id> --dry-run|--apply --format json
```

Add `--source iCloud` or an exact source identifier when explicit selection is
needed. Selection fails closed unless the source is a uniquely verified iCloud
CalDAV source containing reminder lists. Query defaults to incomplete reminders;
due boundaries require ISO 8601 timestamps with explicit offsets. Results use
deterministic chronological ordering and an anchor cursor bound to privacy-hashed
filters and the selected list set. Reusing it after changing filters/lists, or
after its anchor was removed or changed, is rejected. Incomplete-reminder due
ranges are passed to EventKit before fetching. Fetches time out after 10 seconds,
propagate task cancellation, and reject results over 5,000 reminders. EventKit
still materializes its result array before the adapter can enforce that cap, so
the cap is a response-safety boundary rather than a strict peak-memory bound.

Start and due values preserve EventKit `DateComponents`: `value`, `hasTime`,
`floating`, and `timeZone` distinguish date-only, floating timed, and IANA-zone
timed values. The read contract includes `alarms` and `recurrenceRules` arrays
as well as their compatibility presence flags. Relative, absolute, and location
alarms are readable; location-alarm writes remain outside 0.4. Persisting
create, partial edit, complete/reopen, and single-item delete are implemented.

`create --dry-run` validates and normalizes an unsaved draft without calling
`EKEventStore.save`. It resolves the target writable list using `listID`, then
the writable system default within the selected iCloud source, then a sole
writable iCloud list. Ambiguity fails closed. The preview deliberately has no
`id`. Unknown top-level JSON fields are rejected to catch Agent typos.

`create --apply` saves once through EventKit and immediately reads the returned
opaque ID. `verification: "readback_confirmed"` is the strong success state.
`save_accepted_readback_pending` means EventKit accepted the save but immediate
read-back was not visible; preserve the returned ID and do not retry automatically.
`--idempotent` stores only a SHA-256 input fingerprint, opaque Reminder/list IDs,
and creation time in a private 60-second local receipt; it never stores title,
notes, URL, alarm, or recurrence content.

Edit JSON is a partial patch. Omitted fields stay unchanged; `null` clears
`notes`, `url`, `start`, `due`, `alarms`, or `recurrenceRules`; a supplied value
replaces the field. `title`, `priority`, and `listID` cannot be null. Completion
is intentionally rejected here and uses the separate complete/reopen commands.
An alarm patch is rejected when the existing reminder has a read-only location
alarm, preventing silent data loss. Apply saves once and uses the same no-retry
read-back states as create. Real edit apply verification passed in the disposable
gate and final cleanup found zero matching reminders.

`complete` sets completion state and an explicit completion timestamp; `reopen`
clears both. Repeating the requested target state returns `already_completed` or
`already_incomplete` without saving. For a recurring reminder, completion can
make the next incomplete occurrence visible; it is returned separately as
`nextOccurrence`. Real complete/reopen apply and repeated no-op verification passed.
The separate recurring-completion gate also passed against local iCloud with
zero fixture residue. EventKit reused the opaque reminder ID while advancing the
due date, so callers must not use an ID change as proof of occurrence advance:

```text
bash scripts/run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"
```

Delete requires a preview or the exact confirmation phrase:

```text
mpia reminders delete --id <opaque-reminder-id> --dry-run --format json
mpia reminders delete --id <opaque-reminder-id> --apply --confirm "DELETE REMINDER" --format json
```

`absence_confirmed` means the removed opaque ID no longer resolves.
`remove_accepted_readback_pending` means EventKit accepted removal but immediate
absence verification is inconclusive; do not retry automatically and use `get`.

The disposable real iCloud create/get/edit/complete/reopen/delete gate passed
locally and verified a final matching count of zero. Unit, release, read, and dry-run gates do not write
reminders. Any rerun still requires explicit authorization:

```text
bash scripts/run_local_reminders_integration.sh --with-writes --confirm "REMINDERS CRUD TEST"
```

```json
{
  "title": "Prepare weekly report",
  "listID": null,
  "notes": null,
  "url": null,
  "priority": "high",
  "start": null,
  "due": {"value":"2026-08-17","timeZone":null,"hasTime":false,"floating":true},
  "alarms": [{"relativeMinutes":-10}],
  "recurrenceRules": []
}
```

See the [Reminders 0.4 architecture draft](development/reminders-adapter-architecture.md).

## Mail (0.2)

Mail 0.2 is read-only. It does not send, draft, reply, forward, move, archive,
delete, or flag messages, and it does not modify mailboxes, accounts, or Mail
preferences. Unsupported write-like commands return a usage error before Mail
data is accessed.

Run the read-only capability check:

```text
mpia mail doctor --format json
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
mpia mail accounts --format json
mpia mail mailboxes --format json
mpia mail mailboxes --account-id <opaque-account-id> --format json
```

Account IDs are derived opaque local scopes; raw account authorities and full
mailbox URLs are not returned. Mailbox and message IDs are also opaque and must
be treated as adapter-owned values.

List conversation groups reported by the local Mail schema:

```text
mpia mail threads --limit 50 --format json
```

Only explicit positive `conversation_id` values are grouped. The response
contains opaque thread IDs, message counts, and the latest received timestamp;
it does not infer relationships from subject or participants. Mail.app
fallback does not provide this command.

Search cached message bodies without launching Mail.app:

```text
mpia mail search --text "project alpha" --limit 20 --format json
```

This command reads only locally cached EMLX text. It scans at most 200 metadata
candidates and has a one-second budget. Missing, partial, malformed, or
truncated cache content is reported through `limitations`; a no-match result
is not proof that uncached or remote messages do not contain the term. The
command never falls back to Mail.app or remote content.

When the V10 schema/FDA fast path is unavailable, the CLI may use Mail.app only
if Mail is already running and Automation is authorized. This metadata fallback
has a five-second Apple Event timeout and hard caps of 32 accounts, 200 top-level
mailboxes, and 25 message candidates. Its query result is always `incomplete`,
has no cursor, and reports `backend: "mail_app"` plus the fallback reason.
Fallback `ambx_`/`appmsg_` IDs are local adapter values and are not interchangeable
with SQLite IDs. Raw export and attachment verification remain fast-path-only.

Query bounded message metadata:

```text
mpia mail query --unread --limit 50 --format json
mpia mail query --mailbox-id <id> --subject <text> --format json
mpia mail query --from <text> --received-after 2026-07-01 --format json
mpia mail query --cursor <cursor> --limit 50 --format json
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
mpia mail get --id <id> --format json
mpia mail get --id <id> --content text --format json
mpia mail get --id <id> --content raw --output message.eml --format json
mpia mail get --id <id> --content raw --output -
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
mpia mail reveal --id <id> --format json
```

`reveal` may launch and activate Mail.app. It uses the same opaque local ID and
does not intentionally change read, flag, mailbox, or message data.

Cross-check attachment metadata without exporting attachments:

```text
mpia mail attachments verify --id <id> --format json
```

The verifier returns only SQLite and MIME counts, cache state, and whether a
complete cached EMLX matched. It does not return names, paths, or payloads.
Partial or missing EMLX is always `incomplete` and never `matched`, even if the
currently visible counts happen to agree.

Export cached attachments explicitly:

```text
mpia mail attachments export --id <id> --output ./attachments --format json
```

Export requires the SQLite/EMLX fast path, creates the output directory if
needed, rejects path traversal and unsafe filenames, refuses to overwrite an
existing file, and caps each attachment at 20 MiB. Mail.app fallback and
remote attachments are never used.

## Contacts

List available Contacts containers:

```text
mpia contacts containers --format json
```

The default selector is the verified iCloud container. A command may select it
explicitly with `--container iCloud`, or use the exact iCloud container identifier from
the list:

```text
mpia contacts list --container iCloud --format json
mpia contacts get --external-id <id> --container <icloud-container-id> --format json
```

An unknown or non-iCloud container is an error; the CLI never silently falls
back to a local or Exchange account.

The current version writes only to the iCloud Contacts container:

```text
mpia contacts container
```

If no iCloud container is available, all writes are rejected rather than falling back to a local or other account.

Export a JSON snapshot:

```text
mpia contacts export --format json
mpia contacts export --format json --output contacts-snapshot.json
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
mpia contacts permission
mpia contacts count
mpia contacts count --format json
```

JSON responses use contract version `0.1`, independent of the CLI release
version. Successful envelopes contain `ok`, `contractVersion`, and `data`;
errors contain `ok`, `contractVersion`, and `error`.

Read records as JSON:

```text
mpia contacts list --format json
mpia contacts get --external-id <id> --format json
```

Bounded Contacts pages use the shared pagination contract:

```text
mpia contacts list --limit 50 --format json
mpia contacts list --limit 50 --cursor <opaque-cursor> --format json
mpia contacts query --kind organization --limit 50 --format json
```

Paged responses contain `items`, `limit`, `nextCursor`, `truncated`, and
`complete`. Contact cursors are adapter-owned opaque values; Agents must pass
them back unchanged and must not derive offsets from them.

Mail query responses now expose the same canonical `items` field. The existing
`messages` field remains as a compatibility alias for 0.2 clients. Mail.app
fallback remains explicitly incomplete and does not fabricate a cursor; its
limitations explain why pagination cannot resume in that backend.

Search with one or more conditions. Conditions use AND semantics; at most three distinct fields are allowed:

```text
mpia contacts query --name "Ada"
mpia contacts query --kind organization
mpia contacts query --phone "+1 555"
mpia contacts query --email "ada@example.com"
mpia contacts query --url "example.com"
mpia contacts query --organization "Example"
mpia contacts query --postal-code "10001"
```

Create from JSON. Always inspect a dry run before applying:

Every contact created through the CLI must include `externalID` in the JSON.
Contacts that originated outside the CLI may still be read without an external
ID, but the CLI will not create or manage a new record without one.

```text
mpia contacts create --input contact.json --dry-run
mpia contacts create --input contact.json --apply
cat contact.json | mpia contacts create --stdin --dry-run
cat contact.json | mpia contacts create --stdin --apply --idempotent
mpia contacts edit --external-id <id> --input contact.json --dry-run
mpia contacts edit --external-id <id> --input contact.json --apply
cat patch.json | mpia contacts edit --external-id <id> --stdin --dry-run
```

The first Contacts version distinguishes `person` and `organization`. `external_id` is stored only in a URL labeled `mpia-cli`, using the form `mpia://ext-id/<id>`. Other URL labels are ordinary URLs. The CLI selects the verified iCloud container by default; `--container iCloud` or the exact identifier can be used explicitly.

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

If a write reports CoreData error `134092`, macOS may have a corrupted or unsavable Contacts record. Preserve the JSON representation, then explicitly delete and recreate the contact before retrying. `mpia` never performs that destructive recovery automatically.

Set a contact image through a separate argument instead of embedding image data in the regular contact JSON:

```text
mpia contacts edit --external-id <id> --image ./avatar.png --dry-run
mpia contacts edit --external-id <id> --image ./avatar.png --apply
```

To verify an existing avatar without writing anything:

```text
mpia contacts avatar verify --external-id <id> --format json
```

The result is `readback_confirmed`, `not_available`, or
`verification_unknown`. A false lightweight preflight is reported as
`verification_unknown` rather than forcing a risky `imageData` read.

When an existing iCloud record cannot safely be edited in place, use the
separate replacement flow. It preserves the JSON contact fields but creates a
new Contacts record, so it requires an explicit confirmation:

```text
mpia contacts avatar replace --external-id <id> --image ./avatar.png --dry-run
mpia contacts avatar replace --external-id <id> --image ./avatar.png --apply --confirm "RECREATE CONTACT"
```

Images are limited to 10 MB on input. The processed image is kept within 1024 px on its longest side and 200 KB. Invalid, oversized, or uncompressible images are rejected before the contact is modified.

Regular edits are partial updates: omitted fields are preserved, while an explicit `null` clears that field.

### Metadata policy (0.1)

`metadata` is part of the JSON contract. Version 0.1 preserves it in JSON reads, edit previews, and exports, but does not write it into Apple Contacts. This avoids encoding project-private structure into Notes or another contact field.

Delete one contact by external ID. Preview first:

```text
mpia contacts delete --external-id <id> --dry-run
```

Apply only with the exact confirmation phrase:

```text
mpia contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
```

Use a separate migration command to change an external ID:

```text
mpia contacts external-id migrate --from <old-id> --to <new-id> --dry-run
mpia contacts external-id migrate --from <old-id> --to <new-id> --apply --confirm "CHANGE EXTERNAL ID"
```

For the complete payload shape, error behavior, and safety rules, see [development rules](development/rules.md). For local verification records, see [local Contacts fixture](development/local-contacts-fixture.md).
