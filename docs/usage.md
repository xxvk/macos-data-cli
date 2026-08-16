# Usage

Starting with 0.9.3, `mpia` accepts only its REST-style CLI surface. The former
adapter/subcommand syntax is removed.

```bash
mpia METHOD "/path" \
  --params '{"selector":"value"}' \
  --body '{"field":"value"}' \
  --dry-run|--apply \
  --confirm "EXACT PHRASE"
```

Only `mpia --help`, `mpia --version`, and `mpia -v` bypass METHOD/PATH. Methods
are case-insensitive and documented in uppercase. Results are always JSON; the
old `--format`, `--input`, and `--stdin` options no longer exist.

## Input contract

- `--params` defaults to `{}` and accepts one strict inline JSON object up to 32 KiB.
- `--body` is accepted only by routes declaring an input schema and is capped at 384 KiB.
- Unknown, duplicate, wrongly typed, and missing required fields fail closed.
- Safety flags cannot self-authorize through JSON.
- File inputs remain paths in params; do not encode image, attachment, or Shortcut bytes in body.
- Inline JSON may be retained in shell history or process arguments. Never use it for secrets.

## Agent and resource discovery

```bash
mpia GET "/agent/help"
mpia GET "/agent/manifest"
mpia HEAD "/agent/version"
mpia OPTIONS "/resources"
```

`GET /agent/manifest` is the sole public runtime source for methods, paths,
params, body schemas, safety, outputs, and exit codes. See the complete
[interactive documentation](https://mpia-cli-doc.vercel.app/).

## Contacts

```bash
mpia OPTIONS "/contacts/permission"
mpia HEAD "/contacts/count"
mpia GET "/contacts/query" --params '{"name":"Ada","limit":20}'
mpia GET "/contacts/get" --params '{"external-id":"person-001"}'
mpia POST "/contacts/create" --body '{"kind":"person","externalID":"person-001","givenName":"Ada"}' --dry-run
mpia PATCH "/contacts/edit" --params '{"external-id":"person-001"}' --body '{"jobTitle":"Engineer"}' --dry-run
mpia PATCH "/contacts/avatar/edit" --params '{"external-id":"person-001","image":"/tmp/avatar.png"}' --dry-run
mpia DELETE "/contacts/delete" --params '{"external-id":"person-001"}' --apply --confirm "DELETE CONTACT"
```

Contacts defaults to the uniquely verified iCloud container. Every created
contact requires an external ID; ordinary edit cannot change it.

## Calendar and Reminders

```bash
mpia OPTIONS "/calendar/sources"
mpia GET "/calendar/query" --params '{"start":"2026-08-16T00:00:00Z","end":"2026-08-17T00:00:00Z"}'
mpia POST "/calendar/create" --body '{"title":"Review","startDate":"2026-08-16T09:00:00+09:00","endDate":"2026-08-16T10:00:00+09:00"}' --dry-run
mpia OPTIONS "/reminders/sources"
mpia GET "/reminders/query" --params '{"status":"incomplete","limit":20}'
mpia POST "/reminders/create" --body '{"title":"Follow up"}' --dry-run
mpia PATCH "/reminders/edit" --params '{"id":"reminder_opaque"}' --body '{"title":"Follow up today"}' --dry-run
```

Both default to the uniquely verified iCloud CalDAV source; use the `source`
param only for explicit selection.

## Notes

```bash
mpia OPTIONS "/notes/permission"
mpia GET "/notes/query" --params '{"limit":20}'
mpia POST "/notes/create" --body '{"folderID":"notesfolder_opaque","title":"Title","bodyFormat":"plaintext","body":"Body"}' --dry-run
mpia PUT "/notes/edit-body" --params '{"id":"note_opaque"}' --body '{"bodyFormat":"plaintext","body":"Replacement","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"<sha256>"}' --dry-run
```

Notes writes retain write-account binding, explicit-folder, concurrency-token,
shared/locked-object, and read-back guards.

## Communications

```bash
mpia OPTIONS "/mail/doctor"
mpia GET "/mail/query" --params '{"unread":true,"limit":20}'
mpia GET "/mail/get" --params '{"id":"msg_opaque","content":"text"}'
mpia OPTIONS "/messages/permission"
mpia GET "/messages/recent" --params '{"limit":20,"service":"imessage"}'
mpia OPTIONS "/phone-calls/permission"
mpia GET "/phone-calls/recent" --params '{"limit":20}'
```

Mail, Messages, and Phone Calls remain read-only. Messages and Phone Calls
require Full Disk Access.

## Photos, Safari, and Shortcuts

```bash
mpia GET "/photos/query" --params '{"start":"2026-08-01T00:00:00Z","end":"2026-08-16T00:00:00Z","limit":20}'
mpia POST "/photos/export" --params '{"id":"photo_opaque","output":"/tmp/photo.jpeg"}'
mpia GET "/safari/bookmarks/list" --params '{"limit":50}'
mpia POST "/safari/reading-list/add" --body '{"url":"https://example.com","title":"Example"}' --dry-run
mpia GET "/shortcuts/list" --params '{"limit":50}'
mpia POST "/shortcuts/run" --params '{"id":"shortcut_opaque","input-path":["/tmp/input.txt"]}' --apply --confirm "RUN SHORTCUT"
mpia POST "/shortcuts/author/validate" --params '{"source":"./managed.cherri"}'
```

Photos and Shortcut bytes remain file-path operations. Safari direct bookmark
and folder writes report `local_only` and do not claim iCloud synchronization.

## Errors and migration

Legacy syntax returns `LEGACY_SYNTAX_REMOVED`, exit 64, and a REST route in
`nextAction`; it never executes. Method mismatches return `METHOD_NOT_ALLOWED`
with allowed methods. Unknown paths return `ROUTE_NOT_FOUND`. Callers should
branch on process exit status first, then inspect JSON `error.code`.
