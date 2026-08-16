# Phone adapter architecture decision (0.9.2)

## Decision

0.9.2 ships a **read-only** `phone-calls` adapter backed by the local Call
History Core Data SQLite store `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`,
using the same fail-closed fast-path pattern already proven by Mail 0.2 and
Messages 0.9.1. There is no public framework for reading call history; the
adapter reads a runtime-fingerprinted, immutable-connection SQLite view and
returns direction, timestamp, duration, and missed state — never the raw
counterparty number or account identifier.

## Why this is the 0.9.2 direction

- **No public read API.** `Phone.app` / `FaceTime.app` have no AppleScript
  scripting dictionary for call history, and CallKit is iOS-only. There is no
  EventKit or other public macOS framework that exposes past calls.
- **`CallHistory.storedata` is the only read path.** It is a Core Data SQLite
  store (`ZCALLRECORD` / `ZHANDLE` / join tables). The schema is versioned by
  Core Data (`DatabaseVersionPerm`), so it must be fingerprinted per macOS
  version and fail closed on mismatch.
- **Reuse Messages/Mail architecture.** Mail 0.2 and Messages 0.9.1 already
  established the required gate: Full Disk Access, runtime schema fingerprint,
  immutable read-only connection, bounded queries, deadlines, and fail-closed
  compatibility. Phone inherits that pattern.

## Baseline and observed schema (macOS 27)

Confirmed locally on macOS 27 with the store opened strictly read-only
(`mode=ro`). `com.apple.callhistory.databaseInfo.plist` reports
`DatabaseVersionPerm = 46`.

Tables observed:

- `ZCALLRECORD` — one row per call record. Key columns for 0.9.2:
  - `Z_PK` — integer primary key (opaque-ID basis).
  - `ZDATE` — TIMESTAMP, **Apple-epoch seconds** with fractional part
    (`unix = ZDATE + 978307200`). Unlike Messages `chat.db`, this is **not**
    nanoseconds.
  - `ZDURATION` — FLOAT, duration in seconds (0 for missed / not-connected).
  - `ZORIGINATED` — INTEGER, direction: `0` = incoming, `1` = outgoing.
  - `ZANSWERED` — INTEGER, whether an **incoming** call was answered.
  - `ZCALLTYPE` — INTEGER, call kind: `1` = audio, `8` = video.
  - `ZHANDLE_TYPE` — INTEGER, participant handle kind: `1` = phone, `2` = email.
  - `ZUNIQUE_ID` — TEXT, a UUID (length 36).
  - Participant PII (never read): `ZADDRESS` (number/address), `ZNAME`,
    `ZLOCATION`, `ZISO_COUNTRY_CODE`, `ZSERVICE_PROVIDER`,
    `ZLOCALPARTICIPANTUUID`, `ZOUTGOINGLOCALPARTICIPANTUUID`, `ZPARTICIPANTGROUPUUID`.
- `ZHANDLE` — participant handles (`ZVALUE`, `ZNORMALIZEDVALUE`). Never joined or
  read; 0.9.2 never returns counterparty numbers.
- `Z_2REMOTEPARTICIPANTHANDLES` — many-to-many join for group-call handles.
- `ZCALLDBPROPERTIES`, `ZEMERGENCYMEDIAITEM`, `ZSAINTDAVIDSCOUNTS` — out of scope.
- Core Data bookkeeping: `Z_METADATA`, `Z_MODELCACHE`, `Z_PRIMARYKEY` (maps
  `Z_ENT` → entity name).

Missed-call semantics (confirmed on 272 live rows):

- Incoming (`ZORIGINATED = 0`) + `ZANSWERED = 0` ⇒ **missed**; every such row
  has `ZDURATION = 0`.
- Outgoing (`ZORIGINATED = 1`): `ZANSWERED` is unreliable (0 even for connected
  calls), so "connected" is derived from `ZDURATION > 0`.

The reader must never assume this schema is stable. It must probe and verify a
bounded schema fingerprint at runtime and fail closed on mismatch.

## Command surface (0.9.2)

- `mpia phone-calls permission` — status-only authorization/readability probe.
  Reports Full Disk Access and store accessibility without prompting.
- `mpia phone-calls recent [--limit N] [--cursor C]` — read-only recent calls,
  newest first, cursor paginated. Returns per call: opaque local ID, direction,
  kind, answered flag, missed flag, duration, and timestamp.
- Read-only only. No placing calls, deleting history, marking read, or any write.

## Contract (metadata-first, no counterparty PII)

```json
{
  "ok": true,
  "contractVersion": "0.1",
  "data": {
    "items": [
      {
        "id": "call_8f2c4e",
        "direction": "incoming",
        "kind": "audio",
        "answered": false,
        "missed": true,
        "durationSeconds": 0.0,
        "at": "2026-08-14T09:12:00Z"
      }
    ],
    "nextCursor": "cur_8f2c4e",
    "complete": true,
    "truncated": false,
    "limitations": ["counterparty identifiers are never returned"]
  }
}
```

Projection and redaction rules (non-negotiable):

- The raw counterparty number / email / name / location / carrier
  (`ZADDRESS`, `ZNAME`, `ZLOCATION`, `ZISO_COUNTRY_CODE`, `ZSERVICE_PROVIDER`,
  `ZHANDLE.ZVALUE`, `ZHANDLE.ZNORMALIZEDVALUE`) is **never** read or returned.
- Raw primary keys and UUIDs never leave the adapter; only an opaque per-item ID
  (`call_…`) and an opaque cursor (`cur_…`) cross the contract.
- `durationSeconds` is rounded to one decimal place; `missed` is derived from
  incoming + unanswered, and `answered` is the incoming answered flag (or
  `duration > 0` for outgoing "connected").
- Live smoke output is aggregate-only (counts, truncation, completeness) and
  must never print numbers, names, or identifiers.

## TCC and consent

- Reading `CallHistory.storedata` requires Full Disk Access for the responsible
  process (the signed app bundle `.build/debug/mpia.app` during development,
  the released bundle in distribution).
- `phone-calls permission` is status-only and must not prompt. There is no
  `--request` path in 0.9.2.

## Component design

- `PhoneStoreLocator` — resolves `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`,
  rejects symlinks and oversized/unsafe files, and reports discovery state.
- `CallHistoryReader` — opens an immutable read-only SQLite connection, verifies
  the schema fingerprint, and runs bounded `recent` queries with a deadline.
- `PhoneOpaqueID` — encodes `Z_PK` and cursor values behind `call_` / `cur_`
  tokens (same base64url scheme as `MessagesOpaqueID`).
- `PhonePagination` — cursor over (`ZDATE`, `Z_PK`); bound to the exact store
  fingerprint so it fails stale after any store change.

## Stable data and privacy rules

- Treat call IDs, handles, and cursors as opaque adapter values.
- Never expose raw `Z_PK`, `ZUNIQUE_ID`, phone numbers, emails, names, or
  locations.
- Never log or print counterparty numbers, names, or identifiers in diagnostics.
- A stale cursor or an unknown schema is fail-closed; never retry automatically.

## Test and compatibility gates

- Unit tests over synthetic SQLite fixtures only (constructed `ZCALLRECORD`
  schema), so no real Call History data is ever read in tests.
- A privacy-minimized live smoke (`scripts/run_phone_calls_read_smoke.sh`)
  prints aggregate counts and truncation status only; it must stop before any
  query when Full Disk Access is unavailable.
- The schema fingerprint must be re-probed on every new macOS version; a
  mismatch disables the fast path rather than guessing.

## Delivery sequence

1. Architecture decision (this document) + Chinese summary.
2. `PhoneStoreLocator` + `PhoneOpaqueID` + `PhoneModels`.
3. `CallHistoryReader` with schema fingerprint and bounded `recent` query.
4. Contract wiring in the registry + CLI dispatch.
5. Synthetic-fixture unit tests.
6. Live smoke (aggregate-only) and `phone-calls permission` verification.
7. README / usage / OpenAPI regeneration.

## Out of scope (0.9.2)

- Placing calls, deleting history, marking read, voicemail, and any write.
- Counterparty name resolution (Contacts join); call-content transcription;
  group-call participant enumeration; and cross-device guarantees.
- FaceTime video detail beyond the `kind` projection.
