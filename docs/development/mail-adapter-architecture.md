# Mail adapter architecture decision (0.2.0)

Status: accepted for implementation planning  
Date: 2026-07-21

## Decision

Version 0.2.0 starts the Mail adapter as a read-only, local-first integration
with the Mail.app data already present on the Mac. Calendar moves to 0.3.

The adapter uses a three-layer read path:

1. Open Mail's local `Envelope Index` SQLite database strictly read-only for
   account, mailbox, message-envelope, count, and metadata queries.
2. Read locally cached `.emlx` or `.partial.emlx` files for raw RFC 822 data,
   parsed headers, bodies, and attachment metadata.
3. Fall back to Mail.app Apple Events when a body is not cached, an account
   type is not represented by `.emlx`, or the user asks to reveal a message in
   Mail.app.

MailKit is not the primary reader. Apple documents MailKit as an app-extension
framework for message actions, compose sessions, content blocking, and message
security; it does not expose a general API for an independent CLI to enumerate
an existing mailbox.

## Why this is the 0.2 direction

- It reads the same local state the user can inspect in Mail.app.
- It works across the accounts already configured in Mail.app without storing
  another provider token.
- SQLite is appropriate for bounded metadata searches and pagination; Apple
  Events remain available for correctness and user-visible fallback behavior.
- The design remains useful as a CLI first. MCP, skills, or other agent layers
  can call the same stable JSON contract later.
- A read-only first release keeps the undocumented store boundary narrow. It
  does not write Mail's SQLite database or cached files.

## Development baseline and current macOS 26 status

The Mail store was previously inspected on a macOS 27 development Mac without
reading or printing message content:

- macOS 27.0, build `26A5368g`; Xcode SDK 26.5.
- Mail data root: `~/Library/Mail/V10`.
- Metadata database: `V10/MailData/Envelope Index` in WAL mode, with the live
  `Envelope Index-wal` and `Envelope Index-shm` sidecars present.
- Relevant tables include `messages`, `mailboxes`, `addresses`, `subjects`,
  `recipients`, `summaries`, and `attachments`.
- This database currently stores `date_received` as Unix-epoch seconds. Epoch
  assumptions must still be tested because the schema is not a public contract.
- Local message bodies exist as `.emlx` files. An `.emlx` starts with a decimal
  byte count and newline, followed by exactly that many RFC 822 bytes and
  optional Apple metadata.
- Mail.app's scripting dictionary exposes accounts, mailboxes, messages,
  subject, sender, content, sent/received dates, message ID, and read status.

These observations are a historical compatibility baseline, not an Apple API
guarantee.

The current development Mac is now:

- macOS 26.4, build `25E241`, Apple Silicon.
- Xcode 26.6, build `17F113`.
- macOS SDK 26.5.

On 2026-07-23, the current macOS 26.4 host was probed read-only without reading
or printing message content:

- `~/Library/Mail/V10` was discovered dynamically; `Envelope Index`, `-wal`, and
  `-shm` are present.
- SQLite opened with `mode=ro`, reports `journal_mode=wal`, and returns
  `quick_check=ok`.
- Core tables and required date, foreign-key, and state columns are readable,
  including `messages`, `mailboxes`, `subjects`, `addresses`, `recipients`,
  `attachments`, and `summaries`; the expected indexes are present.
- The current store exposes about 124,479 message metadata rows and 36
  mailboxes; the Mail root contains about 43,298 `.emlx` files.
- On this V10 store, `mailboxes.source` is null for every mailbox. The 0.2.0-b
  implementation therefore derives account scope from the mailbox URL's scheme
  and authority, returns only a hash-derived opaque account ID, and never emits
  the raw authority or full URL.
- A sampled `.emlx` has the expected decimal RFC 822 byte-count first line and
  subsequent payload container format; no body was read or printed.
- The implemented 0.2.0-c resolver located a complete cached message through the
  variable-depth ROWID path on this host. Text decoding and exact raw export both
  passed a temporary-file smoke test without printing content; the temporary
  files were deleted automatically.

Therefore, the **V10 SQLite/EMLX fast path is compatible and implementable on
the current macOS 26.4 host**. This is not an Apple compatibility guarantee for
the private schema: `mail doctor` must rediscover the version, validate a schema
fingerprint, verify WAL readability, and fail closed when the capability probe
does not match. Full Disk Access and Mail.app Automation were not independently
determined by this SQLite probe and must remain separate reported capabilities.

## Supported baseline: macOS 26

The package deployment target remains macOS 26.0 and implementation must build
against the macOS 26 SDK. The local toolchain currently provides SDK 26.5. The
Mail adapter's planned dependencies (`Foundation`, Apple Events, and system
`sqlite3`) are available at that target. MailKit's relevant symbols are marked
`API_AVAILABLE(macos(12.0))`, so they also compile on macOS 26; their extension
execution model, rather than API availability, is why they are not the mailbox
query path.

`V10` is a Mail data-store version, not a macOS API level. Apple does not publish
it as a compatibility contract. Therefore 0.2.0 defines support as a pair of
runtime capabilities rather than assuming `macOS 26 == V10`:

| Runtime state | 0.2.0 behavior |
| --- | --- |
| macOS 26.x + readable `V10` + recognized schema fingerprint | Full SQLite/EMLX fast path |
| macOS 26.x + a different `V*` or unknown schema | Disable direct-store reads; use bounded Mail.app metadata only when Mail is running and Automation is authorized, otherwise fail closed |
| macOS 26.x + `V10` but no Full Disk Access | Explain FDA; use the same bounded Mail.app metadata fallback when available, otherwise fail closed |
| Mail not configured or no local store | `mail doctor` reports `MAIL_STORE_NOT_FOUND` |
| macOS 27 development machine + recognized `V10` | Compatibility testing only; it does not redefine the release baseline |

`MailStoreLocator` must still discover the highest numeric `V*` dynamically.
The first schema adapter may be named `MailV10Schema`; it activates only after
checking required tables, columns, indexes, timestamp range, and WAL readability.
This satisfies a macOS 26 machine whose Mail store is `V10`, while failing safely
instead of treating `V10` as guaranteed on every macOS 26 installation.

`mail doctor --format json` should expose at least `osVersion`, `sdkBaseline`,
`mailStoreVersion`, `schemaFingerprint`, `fullDiskAccess`, `automation`, and
`fastPathAvailable` so support can be verified on a real macOS 26 host.

## Query complexity and measured latency

Let `N` be total messages, `K` returned rows, `B` RFC 822 bytes for one message,
`F` files under the Mail root, and `df(t)` the document frequency of an FTS
term. The order below prioritizes expected latency and scaling for the operation
each mechanism is intended to perform; complexities with different variables
are not mathematically interchangeable.

| Priority | Query path | Time complexity | Local evidence / expected latency |
| ---: | --- | --- | --- |
| 1 | SQLite exact ROWID/foreign-key lookup | `O(log N)` | Warm median `<0.01 ms`; about `4.7 ms` including a new `sqlite3` process |
| 2 | SQLite indexed page by date/mailbox/subject/recipient | `O(log N + K)` | Warm 50-row median `<0.01 ms`; about `4.5 ms` including process startup |
| 3 | Direct `.emlx` path and byte extraction for a known ID | Path `O(1)`, read/parse `O(B)` | 200 cached samples: `0.19 ms` median, `0.36 ms` p95; MIME parsing adds linear `O(B)` work |
| 4 | Optional local FTS5 body index | Query approximately `O(sum(df(t)) + K log K)`; initial build `O(total cached bytes)` | Prior art reports roughly `7 ms` term search after indexing; not a 0.2.0 dependency |
| 5 | Unindexed SQLite `LIKE '%term%'` over subject/summary | `O(N + K)` (or number of distinct strings scanned) | No-match warm scans on about 124k messages: subject `11.4 ms`, summary `15.5 ms`; grows linearly |
| 6 | Spotlight/`mdfind` | Apple index complexity is unspecified | Often tens to hundreds of ms, but completeness and deterministic pagination are not guaranteed |
| 7 | Targeted Mail.app Apple Event | Local lookup plus IPC; body fetch can add network time | Budget `3 s` for one message; typical local calls may be tens to hundreds of ms |
| 8 | Mail.app enumeration/search | At least `O(N)` plus per-object IPC | Seconds on large stores and may time out; never the preferred full-mailbox path |
| 9 | Recursive filesystem search for `.emlx` | `O(F)` before reading `O(B)` | A no-match walk of the current Mail root took `1.83 s`; prohibited as an automatic query fallback |

The local measurements used a read-only live `V10` store with about 124k
messages, warm filesystem cache, no message content printed, and no JSON/MIME
serialization cost unless stated. They are engineering evidence, not an SLA.

Default execution budgets for 0.2.0 should be conservative:

- indexed SQLite: 100 ms deadline, default `K = 50`, maximum `K = 200`;
- bounded unindexed SQLite scan: 250 ms deadline;
- cached `.emlx`: 100 ms per message before MIME work, with an explicit byte cap;
- targeted Apple Event: 3 seconds for one message, 5 seconds and at most 25
  candidates for a bounded list fallback;
- after an Apple Event timeout, open a 30-second circuit breaker and do not
  automatically retry or escalate to a full filesystem walk.

## Efficiency-first fallback state machine

At process startup, build a capability snapshot once: Mail root/version,
recognized schema, read-only SQLite/WAL access, `.emlx` availability, optional
FTS state, and Automation status. Then choose a plan by operation:

1. **Metadata query:** indexed SQLite -> bounded SQLite scan only when the
   requested predicate has no index -> Mail.app metadata snapshot only when
   SQLite is unavailable, Mail is already running, and Automation is authorized.
   The snapshot is capped at 32 accounts, 200 top-level mailboxes, 25 message
   candidates, and five seconds; it has no cursor and is always incomplete. Do
   not invoke Mail.app after SQLite has returned a complete empty result.
2. **Get a known message:** indexed SQLite locator -> direct `.emlx` -> targeted
   Mail.app Apple Event only when the file is missing/partial -> return explicit
   `metadata_only` if Automation is unavailable.
3. **Body search:** optional local FTS -> Spotlight discovery marked
   `incomplete` -> explicitly bounded recent `.emlx` scan. Full Mail.app or
   filesystem enumeration requires an opt-in slow mode and is not automatic.
4. **Reveal in Mail.app:** resolve the candidate with SQLite first, then send
   one targeted Apple Event. No alternate GUI or Accessibility automation.

Every fallback must preserve semantics and report `backend`, `elapsedMs`,
`fallbackReason`, `cacheState`, `truncated`, and `incomplete`. A faster partial
answer must never be labeled complete. Timeouts, permission failures, and
unsupported schemas are distinct structured errors. There is no provider API,
IMAP, recursive file walk, or GUI automation escape hatch in automatic mode.
Fallback-generated `ambx_` and `appmsg_` selectors are backend-specific opaque
values. An `appmsg_` selector can drive a targeted metadata/text read or reveal,
but raw export and attachment cross-check remain SQLite/EMLX-only. The fallback
does not enumerate nested mailboxes and a no-match result is never complete.

## Options considered

| Technique | Strength | Main limitation | 0.2 decision |
| --- | --- | --- | --- |
| MailKit extension | Public and supported by Apple | Event/extension oriented; no arbitrary mailbox enumeration for a CLI | Do not use as the core reader |
| Apple Events / AppleScript | Controls the real Mail.app; can fetch uncached content; can reveal a message | Automation permission, slower IPC, Mail.app timeouts, careful argument escaping required | Required fallback and visual verification path |
| `Envelope Index` SQLite | Fast local metadata search, counts, flags, mailbox mapping | Undocumented schema, Full Disk Access, row IDs can change | Primary metadata path, read-only only |
| `.emlx` cache | Raw RFC 822 and MIME data without IPC | Partial or missing local files; Exchange/EWS may not materialize them | Primary cached-content path |
| Spotlight / `mdfind` | Public CLI and useful discovery fallback | Index may be incomplete or stale; weak deterministic pagination | Diagnostic fallback only |
| Direct IMAP/provider API | Documented server-side semantics | Duplicates credentials and no longer means "what Mail.app has locally" | Out of scope for this adapter |
| Accessibility/GUI automation | Can drive visible UI | Fragile and grants broad control | Not a core path; avoid in 0.2.0 |
| Private Mail frameworks or database writes | Potentially broad capability | Unsupported, unsafe, and likely to break or corrupt data | Prohibited |

## What MailKit is for

MailKit runs code that Mail.app invokes at specific extension lifecycle points;
it is not a client object model for browsing Mail.app. Its four core uses are:

- **Message actions:** inspect a message as Mail downloads it, optionally ask to
  be called again when the body is available, then mark read/unread, flag,
  color, or move it to Archive/Junk/Trash.
- **Compose sessions:** observe a compose window, annotate or validate recipient
  tokens, provide extension UI, reject an invalid send, or add headers.
- **Content blocking:** provide WebKit content-rule JSON for message display.
- **Message security:** sign, encrypt, decrypt, and present signer/certificate
  information.

Mail supplies `MEMessage` to those callbacks. The framework has no method that
means "list accounts", "search all existing messages", or "fetch message by
ROWID". A future optional companion extension could use
`MEMessageActionHandler` to incrementally feed newly downloaded messages into a
separate local FTS index, but it would not backfill historical mail and would
require a signed host app plus user-enabled Mail extension. That is a possible
0.2.x optimization, not the 0.2.0 core reader.

## 0.2.0 command surface

The first release is intentionally read-only:

```text
macos-data mail doctor --format json
macos-data mail accounts --format json
macos-data mail mailboxes [--account-id <id>] --format json
macos-data mail query [filters] [--limit <n>] [--cursor <cursor>] --format json
macos-data mail get --id <opaque-local-id> [--content metadata|text] --format json
macos-data mail get --id <opaque-local-id> --content raw --output <file|->
macos-data mail reveal --id <opaque-local-id> [--format json]
macos-data mail attachments verify --id <opaque-local-id> --format json
```

Initial query filters should cover account, mailbox, sender, recipient,
subject, received-after/before, unread, flagged, and has-attachment. Results
must be bounded and deterministic. `mail get` defaults to metadata; reading a
body is explicit.

Each result should report provenance rather than hiding fallbacks:

```json
{
  "backend": "sqlite_emlx",
  "cacheState": "complete",
  "limitations": []
}
```

Possible backend values are `sqlite`, `sqlite_emlx`, and `mail_app`. Possible
cache states include `metadata_only`, `partial`, `complete`, and `unknown`.

Not in 0.2.0: sending, drafting, replying, deleting, moving, changing flags or
read status, unrestricted attachment extraction, full-mailbox background
indexing, and arbitrary SQL.

`attachments verify` is a release diagnostic, not extraction. It reports only
SQLite/MIME counts and verification state. It never returns attachment names,
paths, content IDs, or payload bytes; partial EMLX can never produce `matched`.

## CLI grammar and design philosophy

The command grammar is:

```text
macos-data <domain> <operation> [selector] [projection] [rendering]
```

For Mail, `mail` is the domain; query filters and `--id` select data;
`--content` controls how much of the selected message is projected; and
`--format` controls only serialization. This separation prevents a storage or
output decision from changing the semantic meaning of a query.

The design follows these rules:

1. **Discover before querying.** `doctor`, `accounts`, and `mailboxes` establish
   capabilities and scope before message search.
2. **Make cardinality visible.** `query` returns zero to many envelopes; `get`
   resolves exactly one message or returns a structured not-found/stale error.
3. **Default to the least data.** List queries never include bodies. `get`
   defaults to metadata, and body/raw access is explicit.
4. **Make UI effects explicit.** Data reads do not activate Mail.app. Only
   `reveal` asks Mail.app to show a message.
5. **Express intent, not backend.** Normal users do not choose SQLite, EMLX, or
   Apple Events. The planner selects the fastest complete backend and reports
   it in the result. Backend forcing, if added, is diagnostic-only.
6. **Compose with Unix tools and agents.** Successful data goes to stdout,
   diagnostics go to stderr, and callers branch on exit code before decoding
   the versioned JSON envelope.

### Command rationale

| Command | Cardinality / effect | Reason for the shape |
| --- | --- | --- |
| `mail doctor` | One capability report | Mail access is a combination of store discovery, schema, FDA, Automation, cache, and fast-path status, not one permission bit |
| `mail accounts` | Zero-to-many collection | Establishes stable account scope before mailbox/message operations; `accounts` is the read-only collection endpoint, so a redundant `list` is omitted in 0.2.0 |
| `mail mailboxes` | Zero-to-many collection | Separates hierarchy discovery and counts from message search; accepts `--account-id` to resolve multi-account ambiguity efficiently |
| `mail query` | Zero-to-many envelopes | A bounded, cursor-paginated candidate search; it does not fetch message bodies |
| `mail get` | Exactly one message | Separates unique lookup from collection search and makes content projection explicit |
| `mail reveal` | One visible Mail.app action | Keeps Apple Events/UI activation outside pure reads; "reveal" means locate in the source app, not read or export content |

`mail doctor` is non-interactive and side-effect free by default. It must not
launch Mail.app, prompt for Automation, or open System Settings. A helper such
as `--open-settings` must be explicit.

`accounts` and `mailboxes` return stable adapter IDs for scoping. Display names
are not selectors because they can be duplicated, localized, or renamed.
`query` combines typed filters with AND semantics, defaults to `--limit 50`,
caps at 200, and uses a cursor rather than a drifting page number. It never
accepts arbitrary SQL.

### IDs and content projection

The public `--id` is an opaque adapter ID returned by `query`/`get`, not a raw
SQLite ROWID. A response exposes its local scope and the RFC 822 Message-ID
separately:

```json
{
  "id": "mail:v1:opaque-value",
  "idScope": "local",
  "messageID": "<optional-rfc822-id@example.com>"
}
```

The opaque ID lets the adapter change its internal locator encoding while
preserving the CLI contract. It is still local and may become stale after Mail
reindexes or moves data; stale resolution returns `STALE_LOCAL_ID` instead of
silently selecting a different message.

`--content` is a projection, not a format:

- `metadata`: headers, addresses, dates, flags, mailbox, size, and attachment
  metadata; this is the default.
- `text`: safely decoded plain text without loading remote HTML resources.
- `raw`: exact RFC 822 bytes.

Raw RFC 822 is byte-oriented and may be non-UTF-8 or very large, so it must not
be embedded directly in the JSON envelope. `--content raw` requires
`--output <file>` or `--output -`. With a file, stdout contains a small JSON or
human confirmation; with `--output -`, stdout is raw bytes and `--format json`
is invalid.

`--format json` changes only rendering. Human-readable output remains useful at
the terminal; agents request JSON explicitly. `reveal` also accepts
`--format json` so an agent can receive structured confirmation even though the
operation is user-visible.

## Agent and MCP boundary

The Mail implementation belongs in `macos-data`, not in a Codex plugin or MCP
server. The CLI owns path discovery, TCC diagnostics, schema adaptation, MIME
parsing, limits, and the stable JSON contract. This keeps the same audited local
behavior available to a human in Terminal and to any agent.

A future MCP server may translate tools such as `mail_search` and `mail_get`
into CLI calls, and a plugin or skill may document safe prompting workflows.
Neither layer should reopen `Envelope Index`, parse `.emlx`, or hold a separate
mail permission implementation. In particular, installing an MCP package is not
part of the 0.2.0 runtime dependency graph.

## Component design

### `MailStoreLocator`

- Discover `~/Library/Mail/V*` directories dynamically and select the highest
  readable numeric version containing `MailData/Envelope Index`; do not map a
  macOS version to a hard-coded Mail version.
- Support a test/development path override.
- Resolve and standardize every file URL; reject paths that escape the selected
  Mail root, including through symlinks.

### `MailPermissionProbe`

- Distinguish store missing, Mail not configured, Full Disk Access denied,
  schema unsupported, and Automation denied.
- Full Disk Access cannot be silently granted. `mail doctor` must identify the
  responsible process (installed app, terminal, or agent host) and show the
  System Settings path.
- Apple Events require `NSAppleEventsUsageDescription`. A hardened signed app
  also needs `com.apple.security.automation.apple-events`.

### `EnvelopeIndexReader`

- Link the system `sqlite3` library and open with `SQLITE_OPEN_READONLY`.
- Keep the live database and its WAL visible. Do not copy only the main file,
  checkpoint, vacuum, use a read-write connection, or use `immutable=1` against
  the live store.
- Set a small busy timeout, use prepared statements, and expose only compiled,
  allow-listed queries. Never accept SQL fragments from CLI input.
- Probe required tables and columns at startup. Fail closed with a structured
  `MAIL_SCHEMA_UNSUPPORTED` error when the schema is unknown.
- Treat SQLite ROWID as a local locator, not a cross-machine stable ID. Expose
  RFC 822 Message-ID separately and document that it may be absent or duplicated.
- Cap page size and fetch `limit + 1` to emit a definitive `truncated` or cursor
  signal.

### `EmlxReader`

- Resolve message files from the mailbox URL and message ROWID. The V10 layout
  uses a variable-depth digit path derived from `ROWID / 1000`; cover every
  depth with fixtures rather than assuming a fixed tree.
- Parse the length prefix as bytes, not characters, then parse the extracted
  RFC 822 bytes and MIME structure.
- Detect `.partial.emlx` explicitly. Never report an empty partial body as a
  complete empty message.
- Do not load remote HTML resources. Return sanitized text separately from raw
  RFC 822 data.

### `MailAppBridge`

- Use the public Mail.app Apple Events scripting surface. Serialize calls and
  enforce timeouts because Mail.app IPC can stall on large mailboxes or network
  fetches.
- Construct references from validated integer IDs and escaped values. Do not
  interpolate unchecked user text into AppleScript source.
- Keep `reveal` non-mutating: activate Mail.app and select/open the resolved
  message so the user can visually verify what the CLI returned.
- If Apple Events fail, return the original error category (`automationDenied`,
  `mailNotRunning`, `timeout`, or `messageNotFound`) instead of silently
  returning partial data.

## Stable data and privacy rules

- All Mail-store access is local. No email metadata, body, attachment, or
  account identifier is uploaded by this project.
- Diagnostics may record backend, duration, row count, schema capability, and
  hashed correlation IDs. They must not contain subjects, addresses, mailbox
  names, bodies, attachment names, raw RFC 822, or full local paths.
- Metadata queries do not include body text by default. Body reads and
  attachment extraction require explicit commands.
- The adapter never modifies `Envelope Index`, its WAL/SHM files, `.emlx`
  files, Mail preferences, or account configuration.
- Mutating Mail operations, if designed later, must go through a public Mail.app
  automation surface with dry-run/preview and separate confirmations. They must
  never be implemented as SQLite writes.

## Test and compatibility gates

Before 0.2.0 can ship:

1. Add synthetic SQLite fixtures for supported schema variants; do not copy a
   real user's database into the repository.
2. Add `.emlx` fixtures for plain text, HTML, multipart, attachments, Unicode,
   malformed length, and partial messages.
3. Test dynamic `V*` discovery, permission denied, missing WAL, busy database,
   schema drift, pagination, and path traversal.
4. Add a local read-only smoke test that prints counts and redacted hashes only.
5. Test the authorized and denied Apple Events paths with the signed Debug app.
6. Verify on the macOS 26 stable baseline and macOS 27 development baseline.
7. Run `swift test`, CLI contract tests, Release build, signed-app permission
   checks, and installed-binary smoke tests.

## Delivery sequence

- 0.2.0-a: `MailStoreLocator`, permission/schema doctor, fixtures, errors. **Implemented and verified on macOS 26.4.**
- 0.2.0-b: accounts, mailboxes, bounded envelope query, pagination. **Implemented
  and verified read-only on macOS 26.4.**
- 0.2.0-c: `.emlx` raw/text reads and partial-cache reporting. **Implemented and
  verified read-only on macOS 26.4.**
- 0.2.0-d: Apple Events fallback and `mail reveal` visual verification.
  **Implemented and verified with the signed Debug app on macOS 26.4.** Text
  fallback is limited to explicit reads with no exact cached content; raw stays
  cache-only. The bridge serializes events, times out after 3 seconds, opens a
  30-second timeout circuit, and ordinary fallback does not launch Mail.app.
- 0.2.0: documentation, signing/TCC flow, local read-only smoke matrix.

Body-wide FTS indexing and attachment extraction may follow in 0.2.x after the
read-only contract is stable. Calendar begins in 0.3.

The macOS 26.4 live Automation check used the login user's GUI bootstrap
session and successfully revealed a V10-selected message. The latest bounded
200-message sample had no `metadata_only` candidate, so a live body fallback was
not forced; synthetic fixtures verify its success, denial, not-running, lookup,
timeout, and circuit-open paths without exposing personal mail.

The attachment cross-check ran read-only while Mail.app was synchronizing. The
observed V10 store reached 1,146 attachment rows across 509 non-deleted messages;
all 509 attachment-bearing messages resolved to `.partial.emlx`, and the partial
MIME payloads contained no attachment parts to match. This is an explicit
unverified result, not evidence that the SQLite rows are stale. Future bounded
export must require independently available complete content or a separate
public Mail.app path and must not synthesize files from SQLite metadata alone.

The reproducible non-UI local release gate passes on macOS 26.4: 72 tests,
Release build, signed Debug app, and doctor/metadata/content/attachment smoke.
The attended Automation variant is deliberately separate. One run succeeded;
another run while Mail.app was actively syncing returned `MAIL_APP_TIMEOUT` at
the 3-second budget and stopped without retry, validating the timeout boundary.

The privacy-safe forced-fallback smoke also passed in the login user's GUI
session: 3 account scopes, 35 top-level mailboxes, one bounded message result,
and a targeted metadata get through its `appmsg_` selector. JSON stayed in an
auto-deleted temporary directory and no message fields were printed.

## Prior art and evidence

- [Apple MailKit documentation](https://developer.apple.com/documentation/MailKit)
- [Apple WWDC21: Build Mail app extensions](https://developer.apple.com/videos/play/wwdc2021/10168/)
- [Apple `NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- [Apple privacy settings: Full Disk Access and Automation](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)
- [SQLite WAL read-only behavior](https://www.sqlite.org/wal.html)
- [PsychQuant/che-apple-mail-mcp](https://github.com/PsychQuant/che-apple-mail-mcp), MIT: Swift SQLite/EMLX plus AppleScript fallback, including partial-file and variable-depth path lessons.
- [joargp/amcli](https://github.com/joargp/amcli), MIT: small read-only CLI, dynamic Mail-version discovery, doctor flow, and SQL allow-list ideas.
- [imdinu/apple-mail-mcp](https://github.com/imdinu/apple-mail-mcp), GPL-3.0: useful evidence for a separate FTS5 body index; concepts may be studied, but GPL code must not be copied into this MIT repository.
- [macos-cli-tools/apple-mail-cli](https://github.com/macos-cli-tools/apple-mail-cli), MIT: AppleScript command coverage and its performance tradeoffs.
- [openclaw/imsg](https://github.com/openclaw/imsg): precedent for local read-only SQLite plus public AppleScript mutations and explicit permission separation.

External code must not be copied merely because it is public. Reuse requires a
license check, attribution where required, and tests against this project's own
contract and supported macOS versions.
