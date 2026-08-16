# Photos adapter 0.5 architecture

## Status and objective

PhotoKit is a viable public-framework foundation for a macOS Photos adapter.
Version 0.5 starts read-only: authorization discovery, albums, bounded asset
query, one-asset get, metadata, and opaque references. Export is a separate
explicit capability because metadata can be available while original bytes
exist only in iCloud. Import, mutation, and deletion remain outside the first
runtime slice.

## Public API boundary

- Use `PHPhotoLibrary` for `.readWrite` authorization status and requests.
- Use `PHAsset`, `PHAssetCollection`, `PHCollectionList`, `PHFetchOptions`, and
  `PHFetchResult` for reads.
- Use `PHAssetResource` and `PHAssetResourceManager` only for an explicit export
  command; metadata queries must never request media bytes.
- Do not read Photos databases, library packages, caches, or private frameworks,
  and do not automate Photos.app coordinates.
- Public PhotoKit writes are technically possible, but that does not authorize
  write commands in the initial 0.5 surface.

## Authorization contract

`photos permission` reports `not_determined`, `restricted`, `denied`, `limited`,
or `authorized`. Query/get/albums require read access. Limited authorization is
a valid but incomplete view: every response reports the effective scope and
`complete: false`. An empty limited result must never be described as an empty
full library. The CLI does not silently open the limited-library picker.

The executable and signed app Info.plists require
`NSPhotoLibraryUsageDescription`. Add-only permission is insufficient for reads
and is not requested by the read-only MVP.

## Resource and identity model

The unified resource kind is `photos_library`, provider `photos`. PhotoKit
presents one user library that may contain local and iCloud-backed assets; it is
not modeled as a selectable iCloud account/container.

Asset, album, and cursor IDs are adapter-owned opaque values. Internally they may
bind PhotoKit `localIdentifier` values, but callers must not parse them or assume
portability across Macs, libraries, restores, or delete/re-import. Duplicate
album titles are valid, so query selection uses an opaque album ID. Discovery
preserves user folder/album hierarchy and identifies smart albums separately.

## Read model

The initial asset payload contains opaque ID, media type/subtypes, pixel size,
video duration, available creation/modification dates, favorite/hidden/burst/
Live Photo indicators, optional album context, and an exact location only when
the caller passes `--include-location`. `contentAvailability` is `unknown` in
the metadata-only MVP because metadata does not prove that original bytes are
on disk.

Query/get never call `PHImageManager` or `PHAssetResourceManager` and never
trigger iCloud downloads. Hidden assets are excluded unless `--include-hidden`
is explicit.

```bash
mpia GET "/agent/manifest"
```

Discover executable 0.9.3 routes from the manifest; see `docs/usage.md` for examples.

Query uses creation date, requires start before end, and has a bounded range.
Default limit is 50 and maximum is 200. Ordering is creation date descending,
then opaque ID. Pagination uses a filter-bound opaque anchor cursor and reports
`limit`, `nextCursor`, `truncated`, and `complete`.

## Export boundary

Export follows metadata reads and starts with one asset per command. It requires
an output path, never emits binary in JSON/stdout, and refuses overwrite. Network
access defaults to false; an iCloud-only resource returns `content_not_local`
unless the caller explicitly opts in with `--allow-network`. Original, paired
Live Photo, adjustment, and rendered/current resources must remain distinct.
Output is written to a private temporary file and atomically moved only after
success; partial output is removed on failure.

Implemented variants are `original`, `current`, `paired-video`, and
`adjustment-data`. `current` prefers full-size adjusted resources and falls back
to the original resource while reporting the actual resource kind. If a
priority level contains multiple resources, export returns
`PHOTOS_EXPORT_VARIANT_AMBIGUOUS` rather than guessing. Output is mode `0600`;
existing files and stdout output are rejected. The success JSON never echoes the
destination path.

## Deferred write safety

Import, favorite/hidden/location/date edits, album changes, and deletion require
separate TDD gates and `--dry-run|--apply`. Deletion additionally needs an exact
confirmation phrase and Recently Deleted semantics. Real mutation tests may
only import a disposable fixture and must prove cleanup.

## Privacy and acceptance gates

- Never log filenames, locations, local identifiers, album names, output paths,
  or media bytes. Read smoke tests print authorization and aggregate counts only.
- Unit/contract tests use synthetic mapper and query values and never open the
  user's Photos library.
- `scripts/run_photos_read_smoke.sh` is the only live album gate. It prints
  authorization and aggregate kind counts only and stops before fetch when
  access is unreadable.
- When an agent shell is the responsible process, macOS can attribute PhotoKit
  access to that sandbox instead of the CLI app. For a valid local TCC gate,
  install the current bundle at a stable path and run the smoke with
  `MPIA_APP=/path/to/mpia-debug.app`. The script uses LaunchServices
  plus temporary stdout/stderr files, preserving the app identity without
  exposing album titles or identifiers. A direct sandbox result is not valid
  evidence that the app itself was denied.
- The signed app must preserve
  `com.apple.security.personal-information.photos-library`. The release gate
  verifies the entitlement from the signed bundle, not merely from the source
  plist. Ad-hoc rebuilds change the code requirement, so copy without extended
  attributes to a stable path, re-sign there, reset only this bundle's Photos
  entry when needed, and request access through LaunchServices.
- The local full-access gate passed on 2026-08-14 with 34 collections (11 user,
  23 smart, 0 folders), no truncation, and a bounded 30-day asset query/get
  sample (the five-item cap and one successful opaque-ID get). Only aggregate counts were printed; asset and collection JSON stayed
  in a private temporary directory and was removed by the smoke script.
- `scripts/run_photos_export_smoke.sh` performs the real default-offline gate in
  a private temporary directory. On 2026-08-14, five sampled resources were
  iCloud-only; every attempt returned `PHOTOS_CONTENT_NOT_LOCAL`, no network was
  enabled, and no output remained. Later that day, after explicit user approval,
  `--allow-network` exported one original from the same bounded sample, verified
  nonzero byte count and mode `0600`, and removed the private temporary output.
  Ordinary regression still must not enable network access without fresh,
  explicit approval.
- `scripts/run_photos_metadata_smoke.sh` makes the bounded query/get gate
  repeatable. It reads at most five recent assets, passes one opaque ID only
  inside its private temporary directory, and prints schema/count assertions.
- Test permission mapping and Info.plist; opaque IDs; image/video/Live Photo and
  missing metadata; location opt-in; hidden filtering; duplicate album names and
  hierarchy; query validation/order/pagination/cursor binding; limited
  `complete: false`; CLI JSON/help/exit codes; release and regression builds.

## Accepted 0.5 sequence

1. Architecture and authorization foundation.
2. Album discovery.
3. Metadata query/get with pagination.
4. Explicit no-overwrite, network-opt-in single-asset export.
5. Reassess import and narrow metadata writes; deletion remains last.
