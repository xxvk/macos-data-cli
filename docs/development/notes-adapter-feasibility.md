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
  Notes Recently Deleted. Notes' public scripting dictionary exposes no stable
  locale-independent deleted-folder flag, so a normal bounded Apple Events
  query can still observe that recoverable item until it is permanently removed.
