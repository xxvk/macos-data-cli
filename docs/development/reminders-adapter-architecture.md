# Reminders adapter 0.4 architecture draft

Status: accepted 0.4 design baseline; permission, discovery, bounded query/get,
alarm/recurrence mapping, create dry-run/apply, and guarded single-item delete
are implemented. Completion/reopen include safe no-op repeats and recurring
next-occurrence reporting. The disposable create/get/edit/complete/reopen/delete
cleanup gate passed against local iCloud
with final matching count zero.
The separate recurring-completion gate passed against local iCloud with zero
fixture residue.

The adapter uses Apple's public EventKit framework. It must not read or write
Reminders private databases, automate Reminders.app by screen coordinates, or
silently fall back to a non-iCloud account.

## User outcome and MVP boundary

Version 0.4 should let a local Agent inspect and manage personal iCloud tasks
through one stable JSON contract:

- discover sources and reminder lists;
- query all, incomplete, or completed reminders with bounded pagination;
- get one reminder by an opaque machine-local ID;
- create, partially edit, complete/reopen, and delete one reminder;
- represent title, notes, URL, priority, start/due values, alarms, recurrence,
  completion state, and list ownership;
- preview every mutation and verify every applied mutation by reading it back.

Writing location-based alarms, shared-list participant management, list
creation/deletion, attachments, subtasks, tags, and Reminders.app smart-list
semantics are outside the initial MVP. Existing location alarms are reported as
read-only summaries so an edit cannot silently erase them.

## Apple API boundary

- Permission uses `EKEventStore.requestFullAccessToReminders()`. EventKit does
  not offer a read-only Reminders authorization level.
- The app bundle needs `NSRemindersFullAccessUsageDescription`; the deprecated
  `NSRemindersUsageDescription` is not the primary contract.
- Lists are EventKit calendars returned by `calendars(for: .reminder)`.
- Reads use EventKit's all, incomplete, or completed reminder predicates,
  followed by asynchronous `fetchReminders(matching:)`.
- Writes use EventKit save/remove APIs only. Objects and predicates created by
  one `EKEventStore` instance must not be used with another instance.
- EventKit exposes only the first incomplete reminder in a recurring reminder
  set; completing it makes the next occurrence available. The JSON contract
  must preserve this limitation rather than promise Calendar-style occurrence editing.

Official references:

- [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [Creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders)
- [Creating a recurring event or reminder](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event)
- [NSRemindersFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription)

## Permission and iCloud selection

- `reminders permission` reports current authorization and requests full access
  only when explicitly invoked.
- The default source must be one uniquely verified personal iCloud CalDAV source
  containing reminder lists.
- Missing or ambiguous iCloud sources fail closed. Local, Exchange, Google, and
  other sources are never silently selected.
- Reads cover all reminder lists under the selected source unless `--list` is supplied.
- Creation uses the system default reminders list only when it belongs to the
  selected iCloud source and is writable. Otherwise the only writable list is
  selected when exactly one exists; multiple writable lists require explicit
  `listID` and fail closed.
- `macos-data resources` should expose Reminders capability without exposing
  Apple IDs or account addresses.

## Proposed commands

```text
macos-data reminders permission --format json
macos-data reminders sources --format json
macos-data reminders lists --format json
macos-data reminders query [--status incomplete|completed|all] [--due-start <value>] [--due-end <value>] [--list <id|unique-title>] [--title <text>] [--limit <1...200>] [--cursor <cursor>] --format json
macos-data reminders get --id <opaque-reminder-id> --format json
macos-data reminders create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
macos-data reminders edit --id <id> --input <file>|--stdin --dry-run|--apply --format json
macos-data reminders complete --id <id> --dry-run|--apply --format json
macos-data reminders reopen --id <id> --dry-run|--apply --format json
macos-data reminders delete --id <id> --dry-run --format json
macos-data reminders delete --id <id> --apply --confirm "DELETE REMINDER" --format json
```

Permission prompting occurs only through the explicit permission command.

## Proposed JSON model

```json
{
  "id": "reminder_<opaque>",
  "title": "Prepare weekly report",
  "notes": null,
  "url": null,
  "priority": "none",
  "completed": false,
  "completionDate": null,
  "start": null,
  "due": {
    "value": "2026-08-17",
    "timeZone": null,
    "hasTime": false,
    "floating": true
  },
  "hasAlarms": true,
  "hasRecurrenceRules": false,
  "listID": "remlist_<opaque>",
  "listTitle": "Reminders"
}
```

Both `start` and `due` use the same object shape. Reminders may store a date
without a time or time zone, so the adapter must not convert a date-only value
into midnight UTC. Timed values use ISO 8601 plus an IANA time zone; date-only
values use `YYYY-MM-DD`, `hasTime: false`, and a null time zone. Priority is
encoded as `none`, `high`, `medium`, or `low`, not an arbitrary EventKit integer.
The current read slice reports both compatibility presence flags and detailed
alarm/recurrence arrays. Relative, absolute, and location alarms are readable;
location alarms remain explicitly read-only.

## Identifier policy

Version 0.4 does not define or require a custom `externalID`. It preserves the
user's URL and notes, creates no sidecar identity mapping, and uses opt-in
privacy-minimized receipts only for immediate idempotent retries.

`reminder_<opaque>` carries enough adapter-owned opaque identity to try the local
EventKit `calendarItemIdentifier` first and the calendar-server-provided external
identifier second, while filtering by reminder type and selected iCloud source.
This fallback is required because Apple documents that a full sync can invalidate
the local identifier. Multiple or mismatched fallback results fail closed.
Agents must not parse the ID or treat successful resolution as a permanent
cross-system identity guarantee.

## Pagination and query limits

EventKit reminder fetches are asynchronous and can return an unbounded array.
The adapter selects lists first, pushes incomplete-reminder due bounds into the
EventKit predicate, returns at most 200 items, propagates cancellation, enforces
a structured timeout, and keeps notes out of receipts and diagnostics. The
post-fetch 5,000-item cap cannot prevent EventKit from first materializing its
array and therefore must not be described as a strict peak-memory guarantee.
Ordering is deterministic: incomplete items first; dated incomplete items by due
value ascending with undated items last; completed items by completion date
descending; then list ID, normalized title, and opaque ID as tie-breakers. The
opaque anchor cursor binds the filters, selected list set, ordering version, and
last emitted item. If that anchor disappears or changes, pagination fails stale
instead of silently skipping data. Inserts before the anchor do not shift pages.

## Write safety and idempotency

- Every mutation requires exactly one of `--dry-run` or `--apply`.
- Delete apply also requires `--confirm "DELETE REMINDER"`.
- Dry-run produces before/after JSON without calling EventKit save/remove.
- Create dry-run returns an ID-less `ReminderDraft`; it must never fabricate an
  opaque identifier for an unsaved object. Unknown top-level fields fail closed.
- Applied writes are fetched again and return the final saved representation.
- Completing an already-completed reminder and reopening an incomplete reminder
  are safe no-ops with explicit status.
- Idempotent create must reject a non-equivalent retry.
- Create apply records a privacy-minimized 60-second receipt after save and
  before read-back. It contains only hashes, opaque IDs, and time metadata.
- A save accepted/read-back pending result is not a retry signal. Return the
  opaque ID and instruct the caller to use `get`; never auto-delete or re-create.
- Recurring completion must not claim access to hidden future occurrences.

Recurrence read/create/edit/clear is included in 0.4 after basic CRUD. Completion
follows EventKit's current-occurrence model and reads back the next available
incomplete occurrence. Location alarms are readable but any write payload that
tries to create or modify one returns a structured unsupported-field error.

## TDD and release gates

Implementation order:

1. Core contracts, date-component mapping, validation, and errors.
2. Mocked permission, source/list selection, and ambiguity tests.
3. Read-only EventKit store protocol and synthetic query/pagination tests.
4. CLI process tests for help, malformed input, permission denial, and limits.
5. Dry-run create/edit/complete/reopen/delete tests.
6. EventKit writes and read-back verification.
7. Explicit local iCloud integration using disposable reminders only.
8. Release build, installed CLI smoke, documentation, and version audit.

`swift test` and default release gates remain free of personal reminder data and
real writes. The manual write gate creates uniquely marked disposable reminders,
verifies CRUD/completion/reopen/absence, and always attempts cleanup. It is never
CI and requires an explicit confirmation phrase.

The separate recurring gate is:

```text
bash scripts/run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"
```

It creates a two-occurrence daily fixture, completes the current occurrence,
confirms that the next incomplete occurrence has an advanced due date,
cross-checks `nextOccurrence` when immediately available, and removes all
matching fixture items. The verified local behavior reused the same opaque ID;
EventKit does not promise that each visible reminder occurrence has a different
identifier, so identity changes are never an advancement requirement.

## Accepted architecture decisions

- No custom external ID in 0.4; preserve URL and notes.
- Recurrence ships after basic CRUD within 0.4.
- `start` and `due` share one date-component-aware object shape.
- Location alarms are read-only and rejected in write payloads.
- Use a valid iCloud system default list, then the sole writable iCloud list;
  otherwise require explicit list selection.
- Pagination uses the deterministic ordering and filter-bound cursor above.
