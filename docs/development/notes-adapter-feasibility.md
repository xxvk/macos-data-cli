# Notes adapter 0.6 feasibility decision

Status: accepted for a bounded read-only implementation
Date: 2026-08-14

## Decision

Apple does not publish a Notes framework that lets a third-party macOS process
enumerate the user's Apple Notes library. The macOS 26.5 SDK contains no public
`Notes.framework` or `NoteKit.framework`, and generic Core Data, CloudKit, or
Accounts APIs do not grant access to Notes.app's private stores or CloudKit
container.

Notes.app does, however, publish a supported scripting dictionary. Version 4.13
on the macOS 27.0 development host declares accounts, nested folders, notes,
attachments, stable app-owned IDs, dates, sharing and password-protection state,
HTML body, read-only plaintext, attachment URL metadata, and attachment save.
Apple documents scripting dictionaries and Apple Events as the interfaces by
which scriptable applications expose commands and objects.

Therefore 0.6 may implement a useful **read-only Apple Events adapter**. It must
be described accurately as Notes.app Automation, not as a native Notes
framework. It must not inspect Notes databases, CloudKit records, caches,
private frameworks, or GUI coordinates.

The version boundary is now explicit: 0.6.0 is read-only; guarded Notes writes
are planned as 0.6.1. The initial 0.6.1 release scope is create, rename, and move
with dry-run/apply, optimistic concurrency, idempotency where applicable, and
immediate read-back. Existing-note body replacement, attachment mutation, and
delete remain deferred until their separate destructive/rich-content gates pass.

## Proposed 0.6 MVP

```text
macos-data notes permission [--request] --format json
macos-data notes accounts --format json
macos-data notes folders [--account-id ID] [--parent-id ID]
  [--limit N] [--cursor C] --format json
macos-data notes query [--account-id ID] [--folder-id ID]
  [--title TEXT] [--modified-after ISO-8601]
  [--limit N] [--cursor C] --format json
macos-data notes get --id <opaque-note-id>
  [--body none|plaintext|html] [--include-attachments] --format json
```

The default query is metadata-only. Body access is explicit because note bodies
can contain sensitive information and can be much larger than list metadata.
`get` should cap returned body bytes and fail closed when Notes reports a locked
or inaccessible note. Pagination must use adapter-owned opaque cursors and must
declare completeness; Apple Events enumeration cannot promise database-like
performance on a large library.

## Data boundary

Supported in the MVP:

- account and nested-folder discovery;
- note ID, title, creation/modification dates, folder reference, shared state,
  and password-protected state;
- explicit plaintext or HTML body read;
- attachment metadata: opaque ID, name, dates, content identifier, URL, and
  shared state.

Deferred:

- attachment binary export, until one-file output, no-overwrite, byte limits,
  private staging, and cleanup have an independent gate;
- creating or editing folders and notes, despite writable scripting properties;
- deleting or moving notes;
- rendering HTML into Markdown or attempting lossless rich-text conversion.

Not promised by the current public dictionary:

- tags and smart-folder predicates;
- pinned state;
- checklist, table, drawing, scan, collaboration, or mention semantics;
- a lossless attachment graph or a lossless round trip of modern Notes rich
  content.

Links embedded in the HTML body may be preserved as HTML. The adapter must not
claim that parsing those links reconstructs Notes' internal rich-text model.

## Authorization and execution

The responsible signed app requires `NSAppleEventsUsageDescription` and the
`com.apple.security.automation.apple-events` entitlement already used by the
Mail adapter. `notes permission --request` should trigger only the ordinary
macOS Automation prompt. Query commands fail with a stable authorization error
instead of opening Settings or retrying silently.

Every Apple Event call needs a deadline and bounded object count. The adapter
must not launch an unbounded `every note` body fetch. Metadata enumeration and
body retrieval are separate operations, with a circuit breaker after timeout.

## Acceptance gate

1. Synthetic tests cover mapping, opaque IDs, pagination, body opt-in, byte
   limits, locked notes, missing fields, timeout, and stable errors.
2. CLI contract tests prove metadata-only defaults and no body leakage in logs.
3. A stable signed debug app obtains Notes Automation permission through
   LaunchServices.
4. A privacy-safe live gate prints only authorization and aggregate account,
   folder, and note counts.
5. A disposable test note validates one get/read path and is removed with zero
   residue. No existing user note may be modified for the gate.

## Guarded write implementation boundary

The released 0.6.1 implementation adds create, rename, and same-account move. A local
private binding records the opaque account ID that the user attests is iCloud;
the scripting dictionary has no reliable account-type property. Writes require
that binding plus explicit opaque non-shared folder IDs. Rename and move use the
latest modification date as an optimistic concurrency token.

All Notes Apple Events share one serial lock and a five-second deadline. Dry-run
is the default. Apply distinguishes confirmed read-back, accepted save with
pending read-back, and an unknown outcome; Agents must not retry pending or
unknown outcomes. Output and diagnostics contain hashes and byte counts instead
of title or body content. The 0.6.2 development slice adds guarded whole-body
replacement only for notes proven to contain no attachments and only a bounded
simple HTML subset. It requires both the latest modification date and current
plaintext SHA-256, preserves the title as the first line, and verifies the new
plaintext hash after saving. It also adds guarded recoverable single-note
deletion through the public `delete note` command. Delete requires the latest
whole-second modification date, exact `DELETE NOTE` confirmation, a fresh direct
read, and bound-account/non-shared/non-locked scope. Confirmation means the note
left its original folder with the same title hash; the dictionary has no stable,
language-independent Recently Deleted marker. Pending or unknown outcomes must
not be retried. Permanent deletion remains UI-only. Attachment mutation,
cross-account move, and shared/locked writes remain unavailable.

The Notes 4.13 scripting dictionary marks folder `name` writable, exposes folder
`id`, `shared`, and `container`, and includes the Cocoa Standard `make`, `move`,
and `delete` commands. It does not expose a folder modification date. The 0.6.2
development source therefore implements folder create/rename plus guarded empty-folder-delete and move previews
with an exact current-name SHA-256 guard and, for move preview, an exact current-parent guard. JSON
null explicitly selects account root. Default/shared targets, duplicate sibling
names, cross-account moves, cycles, and incomplete bounded graphs fail closed.
The signed-app gate proved nested create, duplicate rejection, and rename. Notes
4.13 folder move could not preserve a confirmable identity: the empty child
disappeared from the enumerable graph and metadata was temporarily invalid.
Apply therefore returns `NOTES_FOLDER_MOVE_UNSUPPORTED` before any Apple Event.
Empty-folder delete preview requires an exact name hash, explicit parent,
non-default/non-shared scope, and fresh zero direct-note and child-folder counts.
The real apply gate invalidated the metadata graph; after Notes restarted, the
child returned with its old name and a new opaque ID. Apply therefore returns
`NOTES_FOLDER_DELETE_UNSUPPORTED` before any write Apple Event.
`scripts/run_notes_folder_integration.sh` is the audit entry point. Its default
mode performs permission, binding, and create-preview checks only; `--apply`
creates an isolated root/destination/child tree and validates create/rename plus
move/delete fail-closed behavior. UI cleanup requires separate action-time
authorization and a final zero-residue query.

On 2026-08-14, that authorized UI cleanup removed the resurrected child, root,
and destination leaf-first. After restarting Notes, the signed app returned a
complete graph with zero matches for all four known opaque IDs and zero folder
names using the gate sentinel prefix.

## Evidence baseline

- Development host: macOS 27.0 build `26A5388g`.
- Toolchain SDK inspected: macOS 26.5.
- Notes.app inspected: version 4.13, bundle ID `com.apple.Notes`.
- The installed Apple-signed Notes scripting dictionary was inspected with
  `sdef`; this is a compatibility baseline, not a promise that Apple will never
  revise the dictionary.
- On 2026-08-14, the stable signed debug app received Notes Automation access
  and the privacy-safe discovery gate passed with one account and 12 folders,
  `complete: true`, no truncation, and no names, scripting IDs, note titles, or
  bodies printed. Temporary JSON was removed by the gate.
- On 2026-08-14, the first account-level metadata enumeration incorrectly
  returned zero notes because Notes 4.13 does not recursively expose nested
  folder notes through `notes of account`. The bridge was changed to bounded
  recursive folder enumeration. The stable-app metadata gate then returned 163
  notes, `complete: true`, no truncation, and creation/modification dates for all
  163 records. The gate printed aggregate counts only and removed its temporary
  JSON on exit.
- On 2026-08-14, a disposable note passed unique-title query, metadata-only get,
  explicit plaintext (116 UTF-8 bytes), and explicit HTML (159 UTF-8 bytes)
  with sentinel and markup checks. The attachment metadata path returned an
  empty, complete list without reading binary contents. The note was moved to
  Notes Recently Deleted and later permanently removed through Notes UI after
  explicit action-time approval. Notes' public scripting dictionary exposes no
  stable locale-independent deleted-folder flag, so UI cleanup plus a final
  signed-app zero-match query is the required cleanup gate.
- On 2026-08-14, a second disposable signed-app gate confirmed guarded body
  replacement end to end: exact current plaintext SHA-256 and modification date,
  dry-run with no mutation, one apply, immediate hash-confirmed read-back,
  rename, and move across two explicit non-shared iCloud folders. The first
  wrapper run stopped before mutation because its eight-second output wait was
  shorter than Notes plus LaunchServices startup; a direct read proved the
  original body was unchanged. The wrapper first used a 20-second process-output
  wait; Xcode 27 app startup/output later exceeded that bound, so it now uses 40
  seconds with stage reporting while each Apple Event retains its five-second
  deadline. After action-time confirmation, only the fixture was permanently
  removed through Notes UI, the unrelated Recently Deleted note was preserved,
  and a signed-app sentinel query returned zero matches.
- On 2026-08-14, an authorized single-note soft-delete gate completed create,
  body edit, rename, and move. The wrapper reached its former 20-second output
  limit during move and failed closed without retrying; a read-only get proved
  that move had succeeded. From that confirmed state, one delete dry-run and one
  `DELETE NOTE` apply returned `readback_confirmed`, zero matches in the former
  folder, and exactly one recoverable match in a system-managed folder.
  After explicit action-time approval, only this fixture was permanently removed
  through Notes UI. One unrelated Recently Deleted note remained, and a final
  signed-app sentinel query returned `complete=true` with zero matches.
- On 2026-08-14, the fixed-path signed debug app first passed the folder gate's
  permission, valid write-account binding, and create-preview checks without a
  write; the subsequent authorized apply evidence is recorded below.
- On 2026-08-14, the authorized folder apply gate proved nested create,
  duplicate-name rejection, rename, and UI cleanup with a final zero-sentinel
  read-back. It also exposed two runtime defects: recursive account enumeration
  produced duplicate folder IDs, and Notes folder move invalidated confirmable
  identity. Root-only enumeration plus graph validation now prevents crashes;
  folder move apply is disabled pending a different design.
