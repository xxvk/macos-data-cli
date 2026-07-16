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

