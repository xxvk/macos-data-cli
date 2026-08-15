# Safari adapter 0.8 architecture

## Decision

Safari 0.8 uses a deliberately hybrid boundary:

- Bookmarks and Reading List reads load a bounded, read-only snapshot of
  `~/Library/Safari/Bookmarks.plist` with Foundation property-list APIs.
- Reading List creation uses Safari's published scripting command
  `add reading list item` through a five-second Apple Event.
- Version 0.8.0 never writes `Bookmarks.plist`, Safari databases, caches, or
  iCloud metadata directly.
- Version 0.8.1 exposes guarded direct plist mutation as an explicitly
  local-only bookmark/folder CRUD contract after the feasibility, recovery,
  atomic-write, rollback, and live read-back gates passed. It does not claim
  iCloud synchronization.

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

### Phase 1 evidence: copy-only round trip

The synthetic TDD gate and an opt-in audit of an auto-deleted private copy of
the live plist passed. The source file was read only and remained byte-for-byte
unchanged. Unknown plist values, child order, POSIX mode, owner, group, and all
source extended-attribute values survived the copy round trip. The gate rejects
symlinks, existing destinations, duplicate UUIDs, unsupported node types, and
any simulated change outside the selected parent ancestry.

Foundation serialization is semantically stable but not byte-preserving for the
live binary plist: the audited source was 914,933 bytes and the output was
914,917 bytes. Consequently, later mutation gates must compare typed canonical
SHA-256 hashes of every untouched subtree. Whole-file byte equality is not a
valid invariant once one node is intentionally changed.

The current macOS execution carrier adds `com.apple.provenance` to rewritten
files and may regenerate its value for each file instance. Its presence is
therefore enforced but its digest is not compared across source, recovery, and
swap candidate. Every other source xattr value must match exactly, and any other
added xattr fails closed.

### Phase 2 evidence: quiescence and recovery

The safety gate checks both the running Safari application and `lsof` holders of
the exact plist before reading. Two snapshots 500 ms apart must match on device,
inode, size, nanosecond mtime, mode, owner, group, complete SHA-256, and hashes of
all xattr values. It then writes an exact recovery copy and a content-free JSON
manifest into a mode-0700 directory; both files are mode 0600. A final process
check and third identical source snapshot are required after backup creation.
Any failure removes incomplete artifacts.

The opt-in live audit passed while Safari was exited: no process held the plist,
the exact recovery and manifest had private permissions, the source remained
unchanged, and the temporary recovery directory was deleted. TDD also caught
that memory-mapped reads can keep the plist open and make the gate block itself;
the gate therefore uses bounded non-mapped reads. This audit is not a mutation
authorization: the complete gate must run again immediately inside the future
attended replacement flow.

### Phase 3 preparation: atomic private-copy mutation

The pre-live writer accepts only a mutation plan bound to the safety snapshot
and an untampered recovery manifest. It creates a same-directory candidate,
flushes its data, restores every source xattr value, and validates mode, owner,
group, SHA-256, and the destination-only provenance policy. Immediately before
replacement it rechecks Safari, open handles, and the complete source snapshot.

Replacement uses Darwin `renameatx_np` with `RENAME_SWAP`, leaving the exact old
file at the candidate path until the new plist, old plist, recovery copy, parser
read-back, and optional caller verification all pass. Any validation failure
swaps the files back and verifies the restored source against the recovery.
Stale gates and tampered manifests are rejected before replacement.

The first live 0.8.3 attempt exposed the provenance behavior at the recovery
validation boundary. Privacy-safe diagnostics identified only the failed field;
the gate was not weakened for any other xattr. Focused regression tests and the
subsequent live create passed with the file-instance exception above.

This flow passed synthetic apply/stale/rollback/tamper tests and an auto-deleted
copy of the live Safari schema. The private-copy run added exactly one bookmark
under the unique built-in `BookmarksBar`, preserved canonical hashes for 206
untouched subtrees, and left the real plist unchanged. Safari UI acceptance and
iCloud synchronization are still unproven and require the separately authorized
live fixture.

The live entrypoint is disabled unless the exact confirmation phrase
`CREATE SAFARI 0.8.1 FIXTURE` is supplied. It creates one bookmark named
`mpia 0.8.1 plist feasibility fixture` under the unique built-in
`BookmarksBar`. The raw fixture UUID and URL are retained only in a mode-0600
receipt beside the recovery files so later cleanup can target exactly that item.
Success must be followed by Safari UI and parser verification; no automatic
retry is permitted.

### Phase 4 result: local-only success, iCloud-sync failure

The exact confirmation was supplied once for session
`3f6c5b6f-aa0c-4a21-98e8-fe66c578a781`. The atomic replacement added one
fixture and retained the exact pre-write plist, manifest, and receipt as private
mode-0600 recovery files. Safari UI displayed the fixture and the public CLI
returned exactly one match.

The Reading List count changed from 89 to zero because the user separately
deleted those entries; it was not caused by the fixture mutation and is excluded
from this gate's safety verdict. Ordinary bookmark/folder payloads changed from
116 to 117, exactly accounting for the fixture, and no pre-existing ordinary
bookmark disappeared.

The fixture did not appear on another device using the same iCloud Safari data.
The result is therefore split: direct `Bookmarks.plist` replacement is proven
for guarded local-only mutation, but it does not create Safari's private sync
transaction and must not be represented as iCloud-capable.

The Apache-2.0
[`chikingsley/safari-bookmarks-mcp`](https://github.com/chikingsley/safari-bookmarks-mcp)
project independently demonstrates local add/edit/move/remove/folder operations
by decoding the plist into a typed tree and writing it back. Its useful patterns
are UUID-or-path resolution, unknown-field preservation, cycle rejection,
dry-run-by-default MCP writes, timestamped backups, same-directory temporary
files, atomic replacement, and mode preservation. These reinforce the local
CRUD contract and test matrix, but do not change the sync verdict.

Its current implementation does not require Safari to quit, detect open handles,
check a stable pre-write hash, coordinate a Safari file lock, preserve owner,
group, ACLs or extended attributes, fsync the file and directory, validate and
roll back after read-back, or generate `Sync.Changes`. A long-lived MCP service
also loads the plist once and can later overwrite concurrent Safari changes.
Its tests use fixture files and contain no live Safari or second-device iCloud
gate; repository Issues are disabled. mpia already has stricter gates for
all of these local-file concerns, so no source code was copied. Only its
operation vocabulary and negative test cases are candidates for adaptation.

The live system contains the private `SafariBookmarksSyncAgent`, but Apple
publishes no supported CLI or public framework call that submits an externally
edited plist to that agent. Restarting or kickstarting this daemon can restart
its process but cannot reliably create a missing change transaction, so the CLI
must not use it as a sync trigger.

Public-source research found one materially different unsupported route.
The actively maintained
[`jerrykrinock/BkmkMgrs`](https://github.com/jerrykrinock/BkmkMgrs) codebase
loads Safari's private framework, saves through `WebBookmarkGroup`, and calls
`BookmarksController.requestSyncClientTriggerSyncForBookmarkGroup`. Current
private SafariCore header dumps also expose `forceBookmarkSync` and
`userDidUpdateBookmarkDatabase`, but exact GitHub code search found no working
standalone CLI that calls `forceBookmarkSync`; our local XPC probe was rejected
for the missing Apple-private entitlement. BkmkMgrs also records that replacing
`SafariBookmarksSyncAgent` with a diagnostic implementation failed. This is
evidence for an independently gated private-framework experiment, not a public
or stable API contract, and repository code must not be copied without an
explicit compatible license.

Apple documents Safari-owned bookmark import/export and, for sync
troubleshooting, toggling Safari under iCloud settings and restarting the
browser or device. The latter is a user recovery operation, not a per-write API.
See Apple's [Safari sync troubleshooting](https://support.apple.com/en-euro/111761)
and [Safari data-transfer format](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari).

For a sync-capable fallback, generate a minimal Netscape Bookmark HTML file and
let Safari import it through its own UI, then perform duplicate checks and a
second-device read-back. Import is a distinct operation, not proof that a
previous direct-plist node was adopted. Until that gate passes, direct writes
must return `syncStatus=local_only` and an explicit `nextAction`.
Apple documents that imported HTML bookmarks are appended after existing
bookmarks in [Safari's import guide](https://support.apple.com/en-gb/guide/safari/ibrw1015/mac),
so duplicate prevention is mandatory.

## Alternative routes for cross-device writes

Safari's scripting dictionary exposes Reading List addition but no bookmark
list/create/update/delete commands. Shortcuts can be evaluated as a wrapper for
available Safari actions, but it adds another user-managed object and does not
currently establish general bookmark CRUD. Safari WebExtension bookmark support
must be feature-detected against the shipping Safari host; WebKit source alone
is not proof that Safari implements the host bridge. Semantic Accessibility is
the last fallback and must not use screen coordinates.

Before those fallbacks, a research-only private-framework probe may dynamically
detect `BookmarksController` and its sync-request selectors without mutation.
On macOS 27 Beta 5, an ephemeral read-only runtime probe successfully loaded
both Safari and SafariCore and found `BookmarksController`, `WebBookmarkGroup`,
`BookmarksUndoController`, `defaultBookmarksFileURL`,
`requestSyncClientTriggerSyncForBookmarkGroup:`, and its
`skipRequestIfNoChanges:` variant. It did not instantiate a bookmark store,
invoke either selector, or read/write bookmark data.

After the exact authorization `TRIGGER SAFARI PRIVATE SYNC PROBE`, one attended
runtime experiment initialized a controller scoped to the verified default
bookmarks path, loaded its group, and invoked the `skipRequestIfNoChanges:NO`
variant exactly once. An initial ordinary-`init` construction stopped before
the selector because it produced no loadable group, so it counted as zero sync
attempts; the corrected scoped initializer passed a separate preflight before
the sole invocation. The launchd agent remained healthy and IPC-active, and no
entitlement rejection was observed, but the bounded unified-log window also
contained no forced-sync completion evidence. Plist device, inode, size, mtime,
mode, and SHA-256 remained unchanged. The outcome was therefore initially
`request_invoked_remote_pending`, not sync confirmation, and it was not retried.
Second-device read-back subsequently confirmed that the fixture did not sync.
A privacy-bounded read-only audit then found the fixture once in the bookmark
tree but found zero entries in the complete `Sync.Changes` queue. The final
result of this probe is `request_invoked_no_queued_change`: invoking the selector
alone does not adopt a direct-plist mutation into Safari's sync journal.

The BkmkMgrs implementation is materially different. It mutates a
`WebBookmarkGroup`, calls the group's private `save`, repairs orphaned change
records while holding Safari's file lock, releases the lock, and only then calls
the one-argument sync-request selector. Its two-argument, supposedly more
aggressive variant is compiled out. Historical comments describe successful
eventual Mac-to-iPad propagation as well as delayed and conflicting iCloud
behavior; they are evidence that the older end-to-end pipeline could sync, not
that the selector alone was sufficient. The repository's February 2026 Safari
test checks local export/import round trips only. A macOS 27 Beta commit changes
the deployment target for an Xcode build bug but provides no macOS 27
cross-device sync gate. There are currently no repository Issues documenting
this path.

Only a separately authorized disposable fixture may advance to
framework-owned create/save/request-sync and second-device verification. It
must fail closed on missing selectors, framework drift, signing/library-load
failure, unknown outcome, or absent remote read-back, and it must never restart
or modify the sync daemon.

The separately authorized macOS 27 Beta 5 fixture completed its full attended
gate. Before touching the live file, an isolated copy proved
create/save/one-matching-`Add`/remove/save with zero residue and zero sync
requests, while the live plist hash stayed unchanged. A retained recovery was
then created under a private `0700` session directory with `0600` plist,
manifest, and receipt files. The live private-framework operation created
exactly one bookmark, `WebBookmarkGroup.save()` returned `2`, read-back found
exactly one matching `Sync.Changes` `Add` record, and the one-argument sync
selector was called exactly once. The second device still did not receive the
fixture, so the final sync verdict is `framework_add_queued_remote_not_observed`:
even a local `Sync.Changes` `Add` is not cross-device proof. The fixture was then
resolved again by its persisted UUID, removed, saved, and verified locally at
zero matches; one cleanup sync request was issued and no retry or daemon restart
was performed. Further synchronization work is deferred to 0.8.8; the former
0.8.2 safety-engine and 0.8.3 CRUD milestones are consolidated into 0.8.1.

One ABI detail matters for future probes: after `save()`, the original
`WebBookmarkLeaf` object may be stale. Cleanup must obtain the persisted opaque
UUID, resolve the current object with `bookmarkForUUID:`, remove that object,
save, and prove zero residue from disk. The private `removeBookmarks:` return
ABI is not a sufficient success signal by itself.
