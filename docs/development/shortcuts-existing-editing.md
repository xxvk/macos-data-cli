# Shortcuts 0.7.2 existing-editing boundary

## Current implemented slices

0.7.2 currently has public read-only acquisition/classification, semantic
planning, Accessibility discovery, and one guarded copy-first mutation:

```bash
mpia GET "/agent/manifest"
```

Discover executable 0.9.3 routes from the manifest; see `docs/usage.md` for examples.

Inspect, plan, UI inspection, and edit-copy dry-run do not mutate any object.
Planning reads the artifact once, verifies the exact input hash, and applies
operations only to an in-memory shadow graph. Edit-copy apply is intentionally
narrow: only the proven replace-text, append-only insert-text, bounded
all-delete, and bounded all-move families can reach the concrete AX session,
and only after exact confirmation. The complete 0.7.2 gates passed before the
source version was promoted.

## Local acquisition rules

- Accept exactly one `.cherri` or `.shortcut` local regular file and require
  `isFileURL` at the low-level reader boundary.
- Open with `O_NOFOLLOW`, then verify `fstat` regular-file metadata.
- Refuse symlinks, directories, empty files, unknown extensions, and files over
  10 MiB.
- Read no Shortcuts SQLite/CloudKit/private-framework state.
- Do not accept an iCloud share link or any URI syntax in this slice. Apple
  documents that creating a link sends Apple a copy for validation and makes the
  link available through iCloud; receiving remains a visible Get Shortcut flow.
- Perform no request, redirect, download, clipboard read, or import. A red/green
  regression proves that even a remote URL whose path aliases an existing local
  fixture is rejected before reading. Future network acquisition requires a
  separate opt-in command and action-time privacy confirmation.

## Privacy-safe result

The JSON result may contain only:

- input SHA-256 and byte count;
- artifact/parse classification;
- bounded visible and unsupported action counts;
- boolean risk and capability flags;
- stable reason enums.

It must not contain the input path, file name, Shortcut name, Cherri source,
action identifiers, parameters, compiler output, or embedded values.

## Capability states

- `managed_source_route`: valid bounded Cherri should use the existing 0.7.1
  managed-source workflow; it is not adopted as an arbitrary existing object.
- `semantic_edit_candidate`: a parseable unsigned artifact whose visible action
  graph uses only the initial text/comment/nothing/output allowlist and whose
  parameters are scalar and non-sensitive. This means only that a future edit
  plan may be generated.
- `manual_migration_required`: opaque or signed data, unsupported actions,
  malformed/unbounded graphs, nested structures such as magic variables or
  attachments, suspected credentials, or device-bound references.

`canApplySemanticEdit` is true only for a validated replace-text-only plan, an
append-only insert-text plan whose graph already contains Text, or a bounded
all-delete plan that retains at least one action, or a bounded all-move plan. A candidate result
alone is not graph proof, apply authorization, or a compatibility promise.

## Read-only edit-plan contract

- Strict top-level fields: `expectedInputSHA256` and `operations` only.
- Support 1...64 sequential `insert_text`, `replace_text`, `delete_action`, and
  `move_action` operations.
- Visible-action indexes exclude terminal output and are evaluated against the
  shadow graph produced by prior operations.
- Text is at most 64 KiB per operation; patch input is at most 256 KiB.
- `replace_text` requires a text action; deletion may not empty the graph; move
  must change index and cannot cross a semantically indistinguishable neighbor.
- The result contains only indexes, counts, input/plan hashes, and per-value
  byte count/SHA-256. It never returns values or action identifiers.
- Hash mismatch returns a stable concurrency conflict. Unsupported artifacts
  stay on the manual-migration route.
- The plan command itself has no apply flag, Apple Event, Accessibility event,
  registry write, or artifact output.

## Read-only Accessibility discovery

- `ui-inspect` checks trust without prompting and never launches or activates
  Shortcuts.app.
- The bridge exposes attribute reads only. There is no AX action, set-value,
  click, typing, coordinate, screenshot, or image-matching interface.
- Traversal stops above 2,000 nodes or depth 32 and reports `unbounded`.
- A candidate needs both a semantic editor marker and toolbar/group/scroll-area
  hierarchy. Generic roles are insufficient; multiple candidates are
  `ambiguous`.
- Output includes status and counts only. AX labels, titles, identifiers, and
  values are ephemeral matching inputs and must never enter JSON or logs.
- Discovery is compatibility evidence only. `canApplySemanticEdit` remains
  false until separate mutation and recovery fixtures pass.

### macOS 27 Beta 5 live discovery gate

- One disposable Shortcut contained one local Text action and no external side
  effects.
- The first run failed closed and revealed the stable editor identifier
  `editor.shortcutname`. The exact normalized marker was added only after a red
  compatibility test.
- The calibrated run found one bounded candidate across two windows and 373
  nodes; no fixture name, action text, label, title, or identifier entered JSON.
- Cleanup used the selected library row and semantic Edit > Delete command.
  Unique-name search returned no results, and final CLI discovery returned zero
  editor candidates across one window and 139 nodes.

### macOS 27 Beta 5 semantic-element calibration

- A second disposable, local-only fixture contained one Text action and one
  Comment action. It was used for read-only element and menu inspection only;
  no edit operation was invoked.
- The editor name is the unique settable `AXTextField` whose identifier is
  `editor.shortcutname`. The action canvas is an outer `AXScrollArea`; each
  calibrated Text/Comment action has a direct title, a `Close` button, and one
  nested scroll area containing exactly one settable `AXTextArea`.
- The action-library results live in a separate scroll area and must never be
  treated as the action canvas. Unknown direct action titles, a missing or
  duplicate value field, multiple editor candidates, depth overflow, or node
  overflow all fail closed.
- Read-only menu inspection found `duplicateShortcut:` for File > Duplicate,
  `duplicateAction:` for action duplication, `rearrangeItemUp:` and
  `rearrangeItemDown:` for reordering, and `insertCommentAction:` for comment
  insertion. These identifiers are compatibility evidence, not mutation
  authorization. The selected action's menu delete item was disabled while its
  text field had focus, so it is not an approved delete mechanism.
- The pure semantic resolver hashes the private shortcut name and action values,
  returns only semantic kinds and element paths, ignores the action-library
  decoy, and has four focused fail-closed/redaction tests.
- Cleanup used recoverable library deletion. Exact-name search returned no
  result and the library count returned to its pre-gate value, proving zero
  fixture residue.

## Guarded mutation coordinator and public replace-text boundary

- Exact confirmation is `EDIT SHORTCUT COPY`, checked before any editor read.
- The coordinator validates hashes and operation fields, then preflights the
  complete plan against the current semantic action state before recovery or
  mutation.
- It refuses direct original-object edits. A recovery candidate must have a
  distinct hashed identity, exactly preserve the original semantic graph, and
  remain the sole bounded editor candidate.
- Insert-text, replace-text, delete-action, and move-action are applied to the
  copy model sequentially. Every bridge operation must be followed by an exact
  semantic read-back.
- A bridge error or read-back mismatch returns `outcome_unknown` with a fixed
  `nextAction`; automatic retry is always false and the original stays intact.
- Results expose hashes, counts, status, and fixed guidance only. They contain
  no Shortcut name, action text, UI label, identifier, or parameter value.
- Eleven synthetic tests prove these coordinator rules. Compatibility is supported
  separately by the disposable macOS 27 Beta 5 live gate.

### Public `edit copy` contract

- Require one strict `--body` JSON object and exactly one of
  `--dry-run`/`--apply`.
- Require the exact visible editor-name SHA-256. The hash is computed over its
  UTF-8 bytes without a newline; the name itself never enters JSON or logs.
- Dry-run validates the private execution plan and returns a redacted preview
  without constructing the concrete system AX bridge.
- Apply requires `--confirm "EDIT SHORTCUT COPY"` before the bridge is created.
- For apply, every operation must be `replace_text`, every operation must be an
  append-only `insert_text` whose index equals the current action count and
  whose graph already contains a Text action, or every operation must be a
  bounded `delete_action` that leaves at least one action, or every operation
  must be a bounded `move_action`. Other insert and mixed-operation apply
  operations return `SHORTCUTS_EDIT_CAPABILITY_UNSUPPORTED` before mutation.
- Result statuses are `preview`, `readback_confirmed`, or `outcome_unknown`;
  automatic retry is always false.

### Private execution binding and guarded bridge

- Strict patch parsing produces both the public redacted plan and a non-Codable
  in-memory execution plan. Its description and debug description are fixed and
  redact all private values.
- Before any editor read, the coordinator proves each private text value matches
  the public byte count and SHA-256. A copied or altered summary cannot execute.
- The plan-bound guarded bridge has no generic click, typing, coordinate, menu,
  or AX-element escape hatch. Its session surface is limited to inspect,
  duplicate, insert/replace text, delete, and move.
- Recovery must happen first and exactly once. Operations must match the bound
  plan in exact sequence; altered, out-of-order, or extra operations fail before
  a session call.
- Any session mutation error permanently poisons the bridge. Retrying the same
  operation through that bridge is rejected even if a caller ignores the
  coordinator's `outcome_unknown` guidance.
- Fifteen edit-plan tests, eleven coordinator tests, eight semantic-edit service tests,
  and five guarded-bridge tests cover this boundary. Four semantic-resolver
  tests initially covered the calibrated Text/Comment graph; visual-order and
  position failure cases now bring the resolver suite to six tests.

### Concrete copy-first Text mutation gates

- A concrete system AX session implements exact File > Duplicate via
  `duplicateShortcut:`, `AXValue` replacement on a resolver-approved Text
  `AXTextArea`, append-only Text insertion, and a synthetically covered
  resolver-bound Close-button delete. Append insertion focuses one
  resolver-approved Text area, invokes exact `duplicateAction:`, verifies that
  the duplicate appeared at graph end, and then changes only that appended
  value. Delete presses only the resolver-bound Close button and waits for the
  exact smaller graph. Move is bounded to resolver-approved actions plus exact
  `rearrangeItemUp:`/`rearrangeItemDown:` and verifies the
  full visual-order graph after every adjacent step. Middle/no-source insert,
  same-index/equal-neighbor move, mixed-operation plans, generic press, generic
  set-value, coordinates, and image matching remain unavailable.
- The driver reads only the exact toolbar name field and the unique split-group
  scroll area with direct Text/Comment titles. It does not traverse the action
  library. The unique main/focused editor is authoritative; a duplicated
  Shortcut leaves the original editor open in the background and must not be
  treated as an ambiguity.
- AX messaging has a five-second deadline. Twelve focused session tests cover
  copy-first replacement, distinct-copy waiting, one-time shortcut duplication,
  append-only action duplication, exact resolved Close-button deletion,
  unsupported operations, confirmed existing-copy recovery paths, and a
  mutation-free read-back of an already deleted copy.
- The disposable macOS 27 Beta 5 fixture proved: original hash match; distinct
  graph-identical copy; Text replacement hash read-back; unchanged Comment;
  and unchanged original after returning to its editor.
- The first live attempt stalled before duplication because it traversed the
  entire action library. After a bounded-subtree fix, duplication succeeded but
  read-back correctly failed closed because both original and copy editors were
  visible. Exact UI inspection proved replacement had not happened, so a
  dedicated recovery path selected the unique main/focused existing copy and
  completed only the pending replacement without duplicating again.
- Both fixture objects were permanently deleted only after a separate explicit
  confirmation. The library count returned from four to two and exact-name
  search returned no results.
- A separately authorized append fixture proved a Text + Comment graph becomes
  Text + Comment + appended Text in the copy, while the original remains exactly
  Text + Comment. Existing values were unchanged and the appended value matched
  its expected SHA-256.
- After separate cleanup confirmation, both append-gate fixtures were deleted
  through Shortcuts UI. The library returned from four objects to two, and exact
  searches for both names returned no results.
- A later authorized delete fixture proved Text + Comment becomes Text only in
  the copy and that the original remains byte-hash-equivalent Text + Comment.
  The first immediate read-back observed Shortcuts' transient stale graph and
  failed closed. A read-only existing-copy recovery then confirmed one Text
  action without re-duplicating or deleting again. The session now polls for the
  exact smaller graph after pressing the resolver-bound Close button.
- Both delete-gate fixture objects were removed from All Shortcuts. Its count
  returned from four to two and exact-name search returned no results.
- A second disposable fixture passed the corrected uninterrupted gate in one
  command: copy, resolver-bound Comment delete, stable one-Text read-back, and
  unchanged-original verification. Both objects were then permanently deleted;
  the library returned from four to two with exact-name zero residue.
- The authorized move fixture copied Text + Comment and invoked exact
  `rearrangeItemUp:` once. Shortcuts visually changed only the copy to Comment +
  Text while leaving ordinary `AXChildren` stale in creation order. The gate
  failed closed, then a read-only recovery proved `AXChildrenInNavigationOrder`
  reports the real visual order. The resolver now accepts that order only when
  count and the complete allowed action-title multiset match, and uses top-left
  AX Y ordering when positions exist. Hash-bound read-back confirmed the moved
  copy and the unchanged Text + Comment original. No second move or duplicate ran.
  After separate action-time confirmation, both fixtures were permanently deleted;
  All Shortcuts returned from four to two and both exact-name searches returned no
  results.
- The fixture harness remains debug-only. The public CLI exposes the proven
  copy-first replace-text, append-only insert, bounded all-delete, and bounded
  all-move paths.
  Fixture recovery controls and generic AX operations remain private.

## Remaining 0.7.2 work

1. Arbitrary-position insertion remains disabled; only the proven append-only
   subset is open.
2. The complete 0.7.2 release gate and version audit must pass before commit and tag.
