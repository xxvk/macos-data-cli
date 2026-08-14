# Shortcuts 0.7.1 managed-source authoring

## Boundary

Shortcuts 0.7.1 is experimental and manages only shortcuts whose `.cherri`
source remains the user's source of truth. It does not adopt or edit arbitrary
existing shortcuts, read the private Shortcuts database, or copy Cherri source
code into this MIT-licensed repository.

Cherri is an optional GPL-2.0 command-line dependency. The adapter invokes an
installed Cherri 2.3.x binary as a separate process. It always passes
`--skip-sign`, `--derive-uuids`, and `--no-ansi`; HubSign and custom signing
servers are never used. macos-data signs the generated unsigned artifact with
the system `/usr/bin/shortcuts sign` command.

## Source policy

- UTF-8 `.cherri`, at most 256 KiB, with exactly one `#define name` of at most
  200 characters.
- Only the bundled `stdlib` and documented `actions/<category>` includes are
  allowed.
- Packages, relative/absolute includes, `#ref`, file embedding, raw actions,
  custom action definitions, and apparent inline credentials fail closed.
- Generated artifacts are limited to 10 MiB and 2,000 actions. Result JSON
  contains hashes, byte counts, action count, compiler/client versions, and
  signing mode only. It never contains source, shortcut name, action
  parameters, compiler stderr, or secrets.
- Compiled `actionCount` excludes the terminal `is.workflow.actions.output`
  node. Apply results return that value separately from
  `observedActionCount`. On macOS 27 Beta 5, Shortcuts Events reports `0` for
  valid Cherri imports even though black-box execution proves the graph works;
  therefore observed count is not graph proof. An output-only artifact is
  rejected because no independently observable action remains.

## 0.7.1 commands

```text
macos-data shortcuts author validate --source <file.cherri> --format json

macos-data shortcuts author build --source <file.cherri> \
  --output <file.shortcut> \
  [--signing-mode people-who-know-me|anyone] --format json

macos-data shortcuts create --source <file.cherri> [--idempotent] \
  [--dry-run] --format json
macos-data shortcuts create --source <file.cherri> [--idempotent] \
  --apply --confirm "CREATE MANAGED SHORTCUT" --format json

macos-data shortcuts update --id <managed-opaque-id> --source <file.cherri> \
  --expected-source-sha256 <sha256> --strategy replace|retain-old \
  [--dry-run] --format json
macos-data shortcuts update --id <managed-opaque-id> --source <file.cherri> \
  --expected-source-sha256 <sha256> --strategy replace|retain-old \
  --apply --confirm "UPDATE MANAGED SHORTCUT" --format json

macos-data shortcuts managed list --format json
macos-data shortcuts managed forget --id <managed-opaque-id> [--dry-run] --format json
macos-data shortcuts managed forget --id <managed-opaque-id> --apply \
  --confirm "FORGET MANAGED SHORTCUT" --format json
```

`validate` compiles only inside a private temporary directory and removes the
artifact. `build` additionally signs and writes a mode-`0600` output, refusing
overwrite. Neither command imports or runs a shortcut. `create` and `update`
also default to preview; only their exact apply confirmations open a visible
Shortcuts.app import.

The private registry stores only opaque shortcut IDs, source and compiled
SHA-256 values, action count, compiler version, and timestamps. Its directory
is mode `0700`, its JSON file is mode `0600`, and writes are atomic. Public
create/update flows write it only after visible import and metadata read-back.
An in-flight or pending receipt is never an automatic retry signal.

`update` accepts only a registry-managed opaque ID and requires the current
source SHA-256 as an optimistic concurrency token. `replace` keeps the visible
name and is allowed only when the previous public count equals the compiled
registry count and the new count changes. A mismatch makes replace
unverifiable and fails closed. `retain-old` compiles a separately named visible candidate using the
suffix ` (macos-data <source-hash-prefix>)`; the registry continues to track the
original `.cherri` source hash, not the temporary renamed compiler input. The
old Shortcut is never deleted first. `managed forget` removes only private
registry/receipt state and never deletes a Shortcut.

## macOS 27 signing finding

An exploratory build that copied an iCloud-backed source file with `cp`
preserved `com.apple.provenance`; Cherri's generated file then inherited an
extended attribute and `shortcuts sign` rejected it as an incorrect format.
The adapter copies source bytes into a private file instead of copying file
metadata. The same Cherri 2.3.0 artifact then signs successfully on macOS 27
Beta 5. Do not reintroduce metadata-preserving source copies into this path.

Run the non-importing gate with:

```text
bash scripts/run_shortcuts_authoring_smoke.sh
```

The disposable visible lifecycle gate is intentionally separate and requires
explicit current-task authorization plus its exact outer confirmation:

```text
MACOS_DATA_CLI=.build/debug/macos-data.app/Contents/MacOS/macos-data \
  bash scripts/run_shortcuts_authoring_integration.sh \
  --apply --confirm "SHORTCUTS AUTHORING CRUD TEST"
```

It covers validate, create preview/apply, black-box run, update preview with a
`retain-old` candidate, second run, UI deletion, registry forget, and zero
residue. The script pauses for the two visible Add confirmations and semantic
UI deletion; it does not use screen coordinates or delete an arbitrary existing
Shortcut. This gate passed on macOS 27 Beta 5 with Cherri 2.3.0. Both versions
returned the exact sentinel output; the public count remained `0`, and cleanup
restored the two original Shortcuts with fixture and registry residue both zero.
Keep `replace` fail-closed on this host. The post-live full Swift suite,
Release build, CLI contracts, non-importing authoring smoke, and version audit
passed before promotion to `0.7.1`.
