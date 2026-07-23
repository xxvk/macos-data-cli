# macos-data-cli Installation

`macos-data-cli` 0.2.0 can be built and installed locally from source. The
public binary is not yet Developer ID signed or notarized.

## Requirements

- macOS 26.0 or newer
- Apple Contacts enabled in iCloud
- Full Xcode compatible with Swift tools 6.2
- Full Disk Access for the responsible process when using the Mail SQLite/EMLX
  fast path
- Mail.app Automation permission for Mail metadata fallback, text fallback, and
  `mail reveal`

## Build and install locally

From the `macos-data-cli` submodule directory:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build -c release
sudo install -m 755 .build/release/macos-data /opt/homebrew/bin/macos-data
```

### Local Debug and Contacts permission

For local development on macOS 26, select the full Xcode toolchain and build
the authorized Debug app:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build_debug_app.sh
open -W .build/debug/macos-data.app --args contacts permission
```

Approve `macos-data.app` under System Settings → Privacy & Security → Contacts.
The raw `.build/debug/macos-data` executable may be treated as a different TCC
identity and is not the correct real-Contacts verification path. See
[`local-debug-and-tcc_CN.md`](docs/development/local-debug-and-tcc_CN.md).

Verify:

```bash
macos-data --version
macos-data --help
macos-data mail doctor --format json
macos-data contacts permission
macos-data contacts container
bash scripts/run_installed_release_smoke.sh
```

The installed-release smoke verifies that the installed version matches
`VERSION`, help starts correctly, the Mail V10 fast path is available, and a
bounded query uses the SQLite backend. It stores JSON in an auto-deleted
temporary directory and prints no mail fields.

The CLI requests Contacts and Mail Automation access through macOS. Contacts
writes target only the verified iCloud Contacts container and are refused when
that container is unavailable. Mail 0.2.0 never writes the Mail store.

The installed raw binary and `.build/debug/macos-data.app` may be treated as
different TCC identities. Use the signed Debug app for development permission
work; grant FDA/Automation to the responsible installed-binary host separately
when needed.

## JSON usage

Use `--format json` for machine-readable success and error responses. See [usage](docs/usage.md) and [development rules](docs/development/rules.md) for the full contract.
