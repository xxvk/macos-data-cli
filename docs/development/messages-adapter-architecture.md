# Messages adapter architecture decision (0.9.1)

## Decision

0.9.1 ships a **read-only** `messages` adapter backed by the local Messages
SQLite store `~/Library/Messages/chat.db`, using the same fail-closed fast-path
pattern already proven by the Mail 0.2 adapter. There is no public framework
for reading message history; the adapter reads a runtime-fingerprinted,
immutable-connection SQLite view and returns metadata plus a bounded,
redacted text projection.

## Why this is the 0.9.1 direction

- **No public read API.** The `Messages.app` scripting dictionary only exposes
  `send`, `login`, `logout` and the `account` / `chat` / `participant` /
  `file transfer` classes. There is no `message` class, so Apple Events cannot
  read past message history — only send new messages.
- **`chat.db` is the only read path.** It is a well-known SQLite database
  (`message`, `chat`, `handle`, `attachment`, and join tables). The schema is
  stable enough to fingerprint per macOS version, and the format is documented
  by prior art (open-source Message readers, forensic tooling).
- **Reuse Mail's architecture.** Mail 0.2 already established the gate the
  roadmap requires: Full Disk Access, runtime schema fingerprint, immutable
  read-only connection, bounded queries, deadlines, and fail-closed
  compatibility. Messages can inherit that pattern rather than invent a new one.

## Baseline and observed schema (macOS 27)

Confirmed locally on macOS 27.0 (`26A5406e`), with `chat.db` opened read-only:

- `message` — `text` (plain body), `attributedBody` (BLOB rich body), `date`
  (Apple epoch seconds), `is_from_me`, `handle_id`, `service`, `account`,
  `is_read`, `is_delivered`, and many flag columns.
- `chat` — `chat_identifier`, `display_name`, `room_name`, `service_name`,
  `account_login`, `is_archived`, and grouping metadata.
- `handle` — participant identifiers (phone numbers / emails) joined through
  `chat_handle_join` and `message.handle_id`.
- `attachment` / `message_attachment_join` — attachment records (out of scope
  for 0.9.1; only counts may be surfaced, never paths or bytes).

The reader must never assume this schema is stable. It must probe and verify a
bounded schema fingerprint at runtime and fail closed on mismatch, exactly like
Mail's `V10` gate.

## Command surface (0.9.1)

- `mpia messages permission` — status-only authorization/readability probe.
  Reports Full Disk Access and `chat.db` accessibility without prompting.
- `mpia messages recent [--limit N] [--cursor C] [--service imessage|sms]`
  — read-only recent messages, newest first, cursor paginated.
  Returns per message: opaque local ID, `service`, `isFromMe`, timestamp,
  conversation ID, and a bounded redacted text projection.
- Read-only only. No send/reply, mark-read, reaction, attachment export,
  conversation deletion, or any write.

## Contract (metadata-first, bounded text projection)

```json
{
  "ok": true,
  "contractVersion": "0.1",
  "data": {
    "items": [
      {
        "id": "msg_8f2c4e",
        "service": "iMessage",
        "isFromMe": false,
        "sentAt": "2026-08-14T09:12:00Z",
        "conversationId": "chat_5d8e2a",
        "text": "投影后的正文，默认截断到 500 字符"
      }
    ],
    "nextCursor": "cursor_8f2c4e",
    "complete": true,
    "truncated": false,
    "limitations": ["body projected and truncated to 500 chars"]
  }
}
```

Projection and redaction rules (non-negotiable):

- Text is a **projection**, defaulting to the plain `text` column. The richer
  `attributedBody` BLOB is parsed only when an explicit future projection flag
  is added; 0.9.1 does not expose it.
- Text is truncated to a hard cap (default 500 characters) and the response
  marks `truncated` when the cap is hit.
- Participant handles, raw local database IDs, account identifiers, and
  attachment paths are **never** returned by default. Only an opaque per-item
  ID and an opaque conversation ID cross the contract.
- Live smoke output is aggregate-only (counts, truncation, completeness) and
  must never print message bodies, handles, or identifiers.

## TCC and consent

- Reading `chat.db` requires Full Disk Access for the responsible process. The
  signed app bundle (`.build/debug/mpia.app` during development, the released
  bundle in distribution) must be granted Full Disk Access.
- `messages permission` is status-only and must not prompt. There is no
  `--request` path in 0.9.1.

## Component design

- `MessagesStoreLocator` — resolves `~/Library/Messages/chat.db`, rejects
  symlinks and oversized/unsafe files, and reports discovery state.
- `MessagesPermissionProbe` — checks Full Disk Access and read access to the
  store without prompting.
- `ChatDbReader` — opens an immutable read-only SQLite connection, verifies the
  schema fingerprint, and runs bounded `recent` queries with a deadline.
- `MessagesMapper` — maps rows to the contract, applying opaque IDs, text
  projection/truncation, and redaction.
- `MessagesPagination` — cursor over (`date`, opaque ID); opaque, bound to the
  exact `chat.db` fingerprint so it fails stale after any store change.

## Stable data and privacy rules

- Treat message IDs, chat IDs, handle IDs, and cursors as opaque adapter values.
- Never expose raw `ROWID`, `guid`, `chat_identifier`, phone numbers, or emails.
- Never log or print body text, handles, or identifiers in diagnostics.
- A stale cursor or an unknown schema is fail-closed; never retry automatically.

## Test and compatibility gates

- Unit tests over synthetic SQLite fixtures only (constructed `chat.db`
  schema), so no real Messages data is ever read in tests.
- A privacy-minimized live smoke (`scripts/run_messages_read_smoke.sh`) prints
  aggregate counts and truncation status only; it must stop before any query
  when Full Disk Access is unavailable.
- The schema fingerprint must be re-probed on every new macOS version; a
  mismatch disables the fast path rather than guessing.

## Delivery sequence

1. Architecture decision (this document) + Chinese summary.
2. `MessagesStoreLocator` + `MessagesPermissionProbe`.
3. `ChatDbReader` with schema fingerprint and bounded `recent` query.
4. `MessagesMapper` + pagination + contract wiring in the registry.
5. Synthetic-fixture unit tests.
6. Live smoke (aggregate-only) and `messages permission` verification.
7. README / usage / OpenAPI regeneration.

## Out of scope (0.9.1)

- Sending, reply, reactions, read receipts, attachment export, and any write.
- Full-text search across bodies; group-conversation participant resolution;
  syncing with iCloud; and cross-device guarantees.
- `attributedBody` rich-text projection (revisit only behind an explicit,
  separately gated flag).
