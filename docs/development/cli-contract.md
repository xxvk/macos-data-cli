# CLI Contract

## JSON envelope

Machine-readable responses use `contractVersion: "0.1"`, independent from the
CLI release version.

| Result | Shape | Exit code |
| --- | --- | ---: |
| Success | `{"ok":true,"contractVersion":"0.1","data":...}` | 0 |
| Unexpected CLI error | JSON `error.code = CLI_ERROR` | 1 |
| Contacts / permission / input error | JSON `error.code = CONTACTS_ERROR` | 2 |
| Contact lookup error | JSON `error.code = CONTACT_QUERY_ERROR` | 3 |
| Mail adapter error | JSON `error.code = MAIL_ERROR` | 4 |
| Mail Full Disk Access required | `MAIL_FULL_DISK_ACCESS_REQUIRED` | 4 |
| Mail schema unsupported | `MAIL_SCHEMA_UNSUPPORTED` | 4 |
| Mail Automation denied | `MAIL_AUTOMATION_DENIED` | 4 |
| Mail.app not running | `MAIL_APP_NOT_RUNNING` | 4 |
| Mail.app event timeout | `MAIL_APP_TIMEOUT` | 4 |
| Mail.app message not found | `MAIL_APP_MESSAGE_NOT_FOUND` | 4 |
| Mail.app timeout circuit open | `MAIL_APP_CIRCUIT_OPEN` | 4 |
| Calendar adapter error | `CALENDAR_ERROR` or `CALENDAR_*` | 5 |
| Calendar full access missing | `CALENDAR_PERMISSION_REQUIRED` / `CALENDAR_FULL_ACCESS_REQUIRED` | 5 |
| Calendar iCloud source missing or ambiguous | `CALENDAR_ICLOUD_SOURCE_NOT_FOUND` / `CALENDAR_SOURCE_AMBIGUOUS` | 5 |
| Calendar/event not found | `CALENDAR_NOT_FOUND` / `CALENDAR_EVENT_NOT_FOUND` | 5 |
| Invalid Calendar JSON, range, or recurrence span | `CALENDAR_INVALID_INPUT` / `CALENDAR_INVALID_DATE_RANGE` / `CALENDAR_RECURRING_SPAN_REQUIRED` | 5 |
| Calendar idempotency mismatch | `CALENDAR_IDEMPOTENCY_CONFLICT` | 5 |
| Calendar conflict scan too broad | `CALENDAR_CONFLICT_SCAN_LIMIT_EXCEEDED` | 5 |
| Usage or invalid query | JSON `error.code = INVALID_QUERY` | 64 |

Errors are written to stderr. Successful JSON responses are written to stdout.
The caller should branch on the exit code first, then inspect `error.code` and
`error.message` when a JSON error envelope is requested.

Mail callers must also branch on `data.backend`. SQLite message/mailbox IDs and
Mail.app fallback `appmsg_`/`ambx_` IDs are backend-specific opaque values. A
fallback query always returns `incomplete: true`, `nextCursor: null`, and
limitations describing the bounded candidate set. A no-match fallback response
must not be interpreted as a complete mailbox search.

Calendar success responses use the same contract `0.1` envelope. Timed Date
values use ISO 8601; all-day start/end values use `YYYY-MM-DD`. Calendar query returns the unified `items`, `limit`,
`nextCursor`, `truncated`, and `complete` fields. `calevent_`, source, calendar,
and cursor IDs are machine-local opaque values and must not be parsed. A moved
event's returned ID replaces the old ID. Recurring edit/delete requires an
explicit `--span this` or `--span future`.
