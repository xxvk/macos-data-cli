# Safari adapter 0.8 architecture

## Decision

Safari 0.8 uses a deliberately hybrid boundary:

- Bookmarks and Reading List reads load a bounded, read-only snapshot of
  `~/Library/Safari/Bookmarks.plist` with Foundation property-list APIs.
- Reading List creation uses Safari's published scripting command
  `add reading list item` through a five-second Apple Event.
- Version 0.8.0 never writes `Bookmarks.plist`, Safari databases, caches, or
  iCloud metadata directly.
- Version 0.8.1 will test direct plist mutation first, as a controlled
  feasibility gate. Other mutation routes are considered only if that gate
  cannot prove local and iCloud safety.

Apple's exported bookmark format also identifies Reading List as the folder
`com.apple.ReadingList`. The live Safari 27 plist uses the same identifier.

## 0.8.0 read contract

The parser accepts binary or XML property lists, caps the input at 32 MiB,
limits traversal to 50,000 nodes and depth 64, and fails closed on malformed
or unknown node types. It separates:

- normal `WebBookmarkTypeList` folders;
- normal `WebBookmarkTypeLeaf` bookmarks;
- the single `com.apple.ReadingList` subtree; and
- unsupported proxy nodes, which are omitted.

Raw Safari UUIDs become adapter-owned SHA-256 opaque IDs. URLs, titles, preview
text, UUIDs, and filesystem paths never enter diagnostics. Query cursors bind
both the filter and exact plist SHA-256, so any Safari change makes an old
cursor stale instead of silently shifting offsets.

Reading List `DateLastViewed` is mapped to `isRead`. Its absence means the local
plist has no viewed timestamp; it is not a broader claim about another device
before iCloud finishes syncing.

## Reading List creation

Input is strict JSON from stdin or one non-symlink local file:

```json
{
  "url": "https://example.com/article",
  "title": "Optional title",
  "previewText": "Optional preview"
}
```

Only HTTP/HTTPS URLs without embedded credentials are accepted. Input is capped
at 16 KiB, URL at 4,096 bytes, title at 500 characters, and preview text at
4,096 bytes. Dry-run must return before constructing or invoking the mutation
bridge. An already-present normalized URL is a safe no-op.

Apply requires Safari Automation permission. The AppleScript is generated with
escaped values and a five-second timeout. A successful Apple Event is followed
by one fresh plist read:

- `readback_confirmed`: the normalized URL is present;
- `save_accepted_readback_pending`: Safari accepted the event but has not yet
  flushed a readable item; query later and never retry automatically;
- `outcome_unknown`: timeout or interrupted Apple Event; query first and never
  retry automatically.

## 0.8.0 live gate evidence

The stable Debug app obtained Safari Automation while retaining readable plist
access. The explicitly authorized disposable add returned
`save_accepted_readback_pending`; the caller did not retry. A subsequent query
using the exact original URL found one opaque item. After separate action-time
confirmation, Safari UI searched the full unique URL and removed that single
result. The filtered UI became empty and the final exact-URL CLI query returned
zero items. No existing bookmark or Reading List item was used as a fixture.

## Why SQLite is excluded

The live machine stores bookmarks and Reading List in `Bookmarks.plist`.
`History.db`, `CloudTabs.db`, and other Safari SQLite stores serve different
features. They are not mutation candidates for this adapter.

## 0.8.1 direct plist mutation gate

Direct mutation is technically small but has an unpublicized sync contract.
The feasibility gate must therefore proceed in this order:

1. Exercise parser/serializer round trips only on synthetic and copied fixtures;
   preserve unknown keys, dates, data values, ordering, mode, ownership, and
   extended attributes.
2. Create a private mode-`0600` recovery backup and record source SHA-256,
   inode, size, mtime, schema version, and xattr names without logging content.
3. Quit Safari and prove there is no Safari process holding the plist. Observe
   a stable file identity twice before replacement. Do not kill unrelated
   iCloud processes or disable Safari iCloud sync.
4. Add exactly one uniquely named disposable folder/bookmark in a short,
   attended window. Use atomic replacement and never rewrite through JSON.
5. Launch Safari and verify the fixture through Safari UI and the 0.8 parser.
6. Require the user to confirm that the fixture appears on a second iCloud
   device. A same-Mac restart is not iCloud synchronization proof.
7. Remove only the disposable fixture, preferably through Safari-owned UI,
   and confirm deletion on both devices. Do not restore the complete backup
   after unrelated Safari changes have occurred.
8. Check for duplicates, missing pre-existing nodes, schema drift, sync errors,
   and unchanged hashes for every untouched subtree before declaring success.

Any resurrection, duplicate, lost node, rejected schema, or unprovable remote
state fails the experiment. It must not automatically retry or graduate to a
public write command.

## Alternative routes if 0.8.1 fails

Safari's scripting dictionary exposes Reading List addition but no bookmark
list/create/update/delete commands. Shortcuts can be evaluated as a wrapper for
available Safari actions, but it adds another user-managed object and does not
currently establish general bookmark CRUD. Safari WebExtension bookmark support
must be feature-detected against the shipping Safari host; WebKit source alone
is not proof that Safari implements the host bridge. Semantic Accessibility is
the last fallback and must not use screen coordinates.
