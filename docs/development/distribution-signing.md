# Distribution and Signing TODO

## Current state

The existing Homebrew Cask distribution path uses an Apple Silicon prebuilt
binary from GitHub Release. Version 0.2.0 has been built, installed, and
verified locally, but its public release asset and Cask update have not been
published. The local binary is not signed with an Apple Developer ID or
notarized and is not a public distribution artifact.

## Future public-release plan

Run the privacy-safe prerequisite audit first:

```bash
bash scripts/check_public_release_prerequisites.sh
```

It verifies version alignment, a clean worktree, Developer ID availability,
the `macos-data-notary` keychain profile, and GitHub CLI authentication. Set
`MACOS_DATA_NOTARY_PROFILE` when using another profile and
`MACOS_DATA_CASK_FILE` when the Tap checkout is available locally. The script
reports only status and never prints credentials or notarization history.

- Enroll in the Apple Developer Program.
- Create a Developer ID Application certificate.
- Build the release binary in a controlled CI environment.
- Sign the binary with `codesign`, hardened runtime, and a secure timestamp.
- Preserve `scripts/macos-data.entitlements`; Mail.app Automation requires
  `com.apple.security.automation.apple-events` when Hardened Runtime is enabled.
- Package the signed binary for distribution.
- Submit the package with `xcrun notarytool`.
- Staple the notarization ticket with `xcrun stapler`.
- Verify with `codesign --verify` and `spctl --assess` on a clean Mac.
- Upload only the signed and notarized asset to the GitHub Release.
- Update the Homebrew Cask checksum and test installation without quarantine overrides.

Signing credentials must remain in CI secrets or the developer's keychain and must never be committed to the repository.

The local ad-hoc Debug app uses the same checked-in Automation entitlement so
development catches entitlement drift before Developer ID signing is available.
It is still not a notarized distribution artifact.
`scripts/run_mail_release_gate.sh` validates the plist, verifies the app signature,
and reads the entitlement back from the signed app rather than trusting the source
file alone.

After direct local installation, `scripts/run_installed_release_smoke.sh`
independently checks the installed version, help entry point, Mail V10 fast
path, and SQLite query backend. Its temporary JSON is automatically deleted and
it prints no message fields.

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

1. Run `scripts/check_public_release_prerequisites.sh` and resolve every failure.
2. Sign, package, notarize, staple, and locally assess the 0.2.0 artifact.
3. Publish the versioned binary to GitHub Release.
4. Update the Homebrew Cask URL, version, checksum, and archive path.
5. Push the Tap change.
6. On a clean local installation, run `brew update` and `brew upgrade --cask macos-data`.
7. Verify `macos-data --version` and one bounded read-only Mail command.
