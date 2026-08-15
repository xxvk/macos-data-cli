# Distribution and Signing TODO

## Current state

The existing Homebrew Cask distribution path uses an Apple Silicon prebuilt
binary from GitHub Release. The published 0.7.2 asset is not signed with an
Apple Developer ID or notarized. Until an Apple Developer account is available,
an explicitly authorized unsigned community release may use the same channel,
provided its GitHub Release clearly states the Gatekeeper boundary. It must not
be represented as Apple-trusted, Developer ID signed, or notarized.

## Future public-release plan

Run the privacy-safe prerequisite audit first:

```bash
bash scripts/check_public_release_prerequisites.sh
```

It verifies version alignment, a clean worktree, Developer ID availability,
the `mpia-notary` keychain profile, and GitHub CLI authentication. Set
`MPIA_NOTARY_PROFILE` when using another profile and
`MPIA_CASK_FILE` when the Tap checkout is available locally. The script
reports only status and never prints credentials or notarization history.
For GitHub CLI failures, follow [GitHub CLI Environment Know-how](github-cli-environment.md)
before deciding that the token is invalid.

When the owner explicitly authorizes the existing unsigned community channel,
run instead:

```bash
bash scripts/check_public_release_prerequisites.sh --allow-unsigned
```

This does not silently bypass the checks: it verifies a clean source tree, the
exact Release binary version, arm64 architecture, valid ad-hoc signature, and
GitHub authentication, while emitting explicit unsigned/notarization warnings.
The Release notes and Homebrew handoff must preserve those warnings. The
default invocation continues to fail closed without Developer ID and the
notary profile.

- Enroll in the Apple Developer Program.
- Create a Developer ID Application certificate.
- Build the release binary in a controlled CI environment.
- Sign the binary with `codesign`, hardened runtime, and a secure timestamp.
- Preserve `scripts/mpia.entitlements`; Mail.app Automation requires
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
brew upgrade --cask mpia
mpia --version
```

If macOS displays:

```text
“mpia” Not Opened
Apple could not verify “mpia” is free of malware...
```

this means the downloaded binary has a `com.apple.quarantine` attribute and is not yet signed and notarized with Apple Developer ID. It does not mean that Homebrew checksum verification failed.

For the current personally controlled local installation, verify the binary and remove only its quarantine attribute:

```bash
which mpia
xattr -l "$(which mpia)"
xattr -d com.apple.quarantine "$(which mpia)"
mpia --version
```

Do not disable Gatekeeper globally. The permanent public-release solution remains Developer ID signing, hardened runtime, notarization, and stapling as described above.

## Release checklist

1. Choose the signed lane or obtain explicit owner authorization for the
   unsigned community lane.
2. Run `scripts/check_public_release_prerequisites.sh`; for the explicit
   unsigned lane, add `--allow-unsigned` and preserve every warning.
3. For the signed lane, sign, package, notarize, staple, and locally assess the
   target-version artifact. For the unsigned lane, verify the arm64 ad-hoc
   signature and publish the Gatekeeper limitation prominently.
4. Publish the versioned binary to GitHub Release.
5. Update the Homebrew Cask URL, version, checksum, and archive path.
6. Push the Tap change.
7. On a clean local installation, run `brew update` and `brew upgrade --cask mpia`.
8. Verify `mpia --version` and one bounded read-only Mail command.
