# Distribution and Signing TODO

## Current state

The Homebrew Cask currently distributes an Apple Silicon prebuilt binary from the GitHub Release. The asset checksum is verified by Homebrew, but the binary is not signed with an Apple Developer ID or notarized. Users may therefore see a Gatekeeper warning after download.

## Future public-release plan

- Enroll in the Apple Developer Program.
- Create a Developer ID Application certificate.
- Build the release binary in a controlled CI environment.
- Sign the binary with `codesign`, hardened runtime, and a secure timestamp.
- Package the signed binary for distribution.
- Submit the package with `xcrun notarytool`.
- Staple the notarization ticket with `xcrun stapler`.
- Verify with `codesign --verify` and `spctl --assess` on a clean Mac.
- Upload only the signed and notarized asset to the GitHub Release.
- Update the Homebrew Cask checksum and test installation without quarantine overrides.

Signing credentials must remain in CI secrets or the developer's keychain and must never be committed to the repository.

## Local workaround

For a release asset whose checksum has been independently verified, a user may remove the downloaded file's quarantine attribute once. This is a local trust decision, not a substitute for signing and notarization.

## Homebrew update and local verification workflow

After the Tap has been updated successfully, the normal local update flow is:

```bash
brew update
brew upgrade --cask macos-data
macos-data --version
```

If macOS displays:

```text
“macos-data” Not Opened
Apple could not verify “macos-data” is free of malware...
```

this means the downloaded binary has a `com.apple.quarantine` attribute and is not yet signed and notarized with Apple Developer ID. It does not mean that Homebrew checksum verification failed.

For the current personally controlled local installation, verify the binary and remove only its quarantine attribute:

```bash
which macos-data
xattr -l "$(which macos-data)"
xattr -d com.apple.quarantine "$(which macos-data)"
macos-data --version
```

Do not disable Gatekeeper globally. The permanent public-release solution remains Developer ID signing, hardened runtime, notarization, and stapling as described above.

## Release checklist

1. Publish the versioned binary to GitHub Release.
2. Update the Homebrew Cask URL, version, checksum, and archive path.
3. Push the Tap change.
4. On a clean local installation, run `brew update` and `brew upgrade --cask macos-data`.
5. Verify `macos-data --version` and one read-only Contacts command.
6. Until signing and notarization are available, document any Gatekeeper warning and local quarantine handling.
