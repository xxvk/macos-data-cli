# macos-data-cli Installation

`macos-data-cli` is currently distributed from source for the 0.1.0 development release.

## Requirements

- macOS 26.0 or newer
- Apple Contacts enabled in iCloud
- Swift/Xcode toolchain compatible with the package

## Build and install locally

From the `macos-data-cli` submodule directory:

```bash
swift test
swift build -c release
sudo install -m 755 .build/release/macos-data /opt/homebrew/bin/macos-data
```

Verify:

```bash
macos-data --version
macos-data --help
macos-data contacts permission
macos-data contacts container
```

The CLI requests Contacts permission through macOS. Version 0.1.0 writes only to the iCloud Contacts container and refuses writes when that container is unavailable.

## JSON usage

Use `--format json` for machine-readable success and error responses. See [usage](docs/usage.md) and [development rules](docs/development/rules.md) for the full contract.

