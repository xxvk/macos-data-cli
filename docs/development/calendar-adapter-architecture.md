# Calendar adapter 0.3 architecture

The Calendar adapter uses Apple's public EventKit framework. It does not read
Calendar's private database and does not use Calendar.app GUI automation or
AppleScript. This document defines the 0.3.0 source-release contract. Public
precompiled distribution status is documented separately.

## Permission and source selection

- Event reads require EventKit `fullAccess`; `writeOnly` is never treated as readable.
- `calendar permission` calls `requestFullAccessToEvents()`.
- The default source must be one uniquely verified iCloud CalDAV source.
- `--source iCloud` or the exact source identifier is accepted; non-iCloud sources are rejected.
- Missing or ambiguous iCloud sources fail closed without falling back to Local,
  Exchange, Google, or another account.
- Queries use all event calendars under the selected iCloud source unless
  `--calendar <identifier|unique-title>` is supplied.
- Creation prefers the system default writable calendar only when it belongs to
  the selected iCloud source. If no default can be verified and several writable
  calendars exist, JSON must specify `calendarID`.

## Commands

```text
mpia calendar permission
mpia calendar sources --format json
mpia calendar calendars --format json
mpia calendar query --start <iso8601> --end <iso8601> [--calendar <id|title>] [--title <text>] [--limit <1...200>] [--cursor <cursor>] --format json
mpia calendar conflicts --start <iso8601> --end <iso8601> [--calendar <id|title>] --format json
mpia calendar get --id <opaque-event-id> --format json
mpia calendar create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
mpia calendar edit --id <id> --input <file>|--stdin --dry-run|--apply [--span this|future] --format json
mpia calendar delete --id <id> --dry-run [--span this|future] --format json
mpia calendar delete --id <id> --apply --confirm "DELETE EVENT" [--span this|future] --format json
```

Timed Calendar dates are ISO 8601 and `timeZone` is an IANA identifier such as
`Asia/Tokyo`. All-day events are floating and use date-only `YYYY-MM-DD` values;
`endDate` is exclusive. The minimal create payload requires `title`, `startDate`,
and `endDate`. `allDay` defaults to false; attendees, alarms, and recurrence rules
default to empty arrays. Attendees are readable but intentionally not writable in 0.3.

## Alarms, idempotency, and conflicts

Each alarm contains exactly one trigger: `relativeMinutes` (for example `-10`)
or an ISO 8601 `absoluteDate`. An edit replaces the alarm set; `"alarms": []`
clears it. Creation removes any EventKit-inherited calendar default alarms before
applying the explicit JSON set.

`create --idempotent` is opt-in. It first uses an immediate visible-event match,
then writes a hashed, privacy-minimized receipt for 60 seconds under
`~/Library/Application Support/mpia-cli/idempotency/calendar`. The receipt
contains only opaque event/calendar IDs and time; no title, notes, URL, location,
or attendee data. A same-slot non-equivalent visible event fails closed.

`calendar conflicts` reports pairwise overlaps using opaque IDs and overlap
intervals. Events whose boundaries only touch do not conflict. A scan exceeding
200 events fails closed and asks the caller to narrow the range.

## Recurrence

Rules explicitly represent frequency, interval, simple weekdays, ordinal
weekdays, month/year positions, and either an end date or occurrence count.
Recurring edit/delete requires `--span this` or `--span future`; the CLI never
guesses the intended series scope.

## Opaque event ID

An ordinary EventKit event identifier cannot safely select every occurrence in
a recurring series. Public `calevent_` IDs therefore bind the local
`calendarItemIdentifier` and occurrence start. Agents must return them unchanged
and must not depend on their encoding. Moving an event can return a new ID and
make the old ID stale. Source, calendar, and cursor IDs are also machine-local
opaque values, not cross-device identifiers.

## Write safety and verification

- Every mutation requires `--dry-run` or `--apply`.
- Delete apply additionally requires `--confirm "DELETE EVENT"`.
- Dry-run builds before/after data without calling EventKit save/remove.
- A real write gate must use a disposable event and verify create, read-back,
  edit, read-back, delete, and absence. Existing user events are never apply fixtures.

```bash
swift test
bash scripts/run_calendar_contract_tests.sh
bash scripts/build_debug_app.sh
bash scripts/run_calendar_read_smoke.sh
bash scripts/run_calendar_dry_run_smoke.sh
bash scripts/run_local_calendar_integration.sh
bash scripts/run_calendar_recurrence_integration.sh --confirm "CALENDAR RECURRENCE TEST"
bash scripts/run_calendar_feature_integration.sh --confirm "CALENDAR FEATURE TEST"
```

The read and dry-run smoke tests retain private JSON only in an auto-deleted
mode-700 temporary directory and print aggregate results. After explicit
authorization, the real EventKit apply integration passed create, read-back,
edit, read-back, delete, and final-absence verification with a disposable event.

The repeatable real gate remains:

```bash
bash scripts/run_local_calendar_integration.sh --with-writes --confirm "CALENDAR CRUD TEST"
```

The separately confirmed recurrence gate creates six disposable occurrences,
checks idempotent retry and alarm read-back, edits/deletes `this` and `future`
scopes, and verifies complete cleanup. It has passed against the local iCloud
Calendar and is never part of `swift test`.

The separately confirmed feature gate creates only uniquely marked disposable
events. It verifies all-day create/edit date-only read-back, relative alarm
read-back, replacement by an absolute alarm, alarm clearing, one strict overlap,
non-equivalent idempotent-create rejection, one adjacent non-overlap, and zero
remaining fixture URLs. It has passed against
the local iCloud Calendar and is never part of `swift test`.
