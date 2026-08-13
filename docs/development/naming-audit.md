# CLI naming and compatibility audit

Status: the second candidate, similar-name, and common package-registry audit
was completed on 2026-08-14. The project owner explicitly rejected `xvk-data`
and decided to retain `macos-data` as the sole canonical command throughout 0.x.
Naming is reviewed again as a 1.0.0 release gate. See
[ADR 0001](adr/0001-cli-name-until-1.0.md).

## Adopted transition constraints

- The complete 0.x line uses `macos-data` as its sole canonical command.
- No new command alias or deprecation process is introduced during 0.x.
- Naming is reviewed before the formal 1.0.0 release; review does not pre-commit
  the project to a rename.
- A CLI rename does not silently rename the stable
  `x-macos-data://external-id/` data contract. Any identifier-scheme change
  requires a separate design, migration command, and compatibility period.
- Compatibility should be described referentially, for example “a native data
  CLI for macOS,” rather than treating an Apple mark as the project's identity.

## Apple naming boundary

Apple's current trademark list identifies both `Mac` and `macOS` as registered
Apple trademarks. Apple's third-party guidelines allow Apple word marks in
referential compatibility phrases subject to their conditions. The guidelines
also describe a limited product-name exception for `Mac` when it is combined
with a non-generic, non-geographic word and does not imply Apple endorsement.

Consequences for this project:

- Lowercase spelling does not by itself make `macos-data` trademark-neutral.
- `mac-data` is not automatically safer: `data` is a generic descriptive word,
  so the documented `Mac` product-name exception is not clearly satisfied.
- Homebrew acceptance is ecosystem evidence, not trademark permission.
- A final public name should preferably avoid both `Mac` and `macOS` and use
  those terms only to describe platform compatibility.

Primary references:

- [Apple Trademark List](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
- [Guidelines for Using Apple Trademarks and Copyrights](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)

This repository records an engineering naming assessment, not legal advice.

## Homebrew namespace snapshot

The updated Homebrew index on 2026-07-23 contained:

| Prefix | Formulae | Casks |
| --- | ---: | ---: |
| `mac*` | 15 | 59 |
| `macos*` | 3 | 0 |

The three `macos*` Formulae were `macos-term-size`, `macos-trash`, and
`macosvpn`. Many `mac*` results refer to MAC addresses, Monkey's Audio, `Mach`,
or `macro`, so raw prefix counts must not be treated as Apple-brand precedents.

## Initial candidate inventory

Exact-name checks covered the current Homebrew Formula/Cask indexes, public
GitHub repository names, and the local executable namespace. They do not cover
registered trademarks, domains, every package registry, or confusingly similar
names.

| Candidate command | Homebrew exact name | GitHub exact-name repositories | Local command | Initial assessment |
| --- | --- | ---: | --- | --- |
| `xvk-data` | available | 0 | available | Strongest exact-name availability; tied to the maintainer namespace |
| `native-data` | available | 1 | available | Clear purpose but generic and already used on GitHub |
| `system-data` | available | 0 | available | Available but broad and weakly distinctive |
| `agent-data` | available | 0 | available | Available but may imply dependence on an Agent platform |
| `data-bridge` | available | 60 | available | Reject: heavily occupied and non-distinctive |
| `os-data` | available | 2 | available | Short but generic and already used on GitHub |

The initial shortlist is therefore `xvk-data`, `system-data`, and `agent-data`.
None is approved. Additional distinctive candidates should be generated before
selection; exact-name availability alone is not enough.

## Second-round shortlist (2026-08-14)

The second round added `xvk-native`, `native-relay`, `framebridge`, `hostscope`,
and `nativeport`, then checked Homebrew, GitHub name search, npm, PyPI, and the
local command namespace. crates.io returned 403 to the automated status check,
so Rust crate availability remains unconfirmed. These checks are not a formal
trademark clearance.

| Candidate | Result | Assessment |
| --- | --- | --- |
| `xvk-data` | No exact Homebrew, GitHub, npm, PyPI, or local-command match | **Rejected**: the project owner does not accept a maintainer namespace as the product name |
| `xvk-native` | Same exact-name result | Alternative; `native` describes implementation less clearly than system data |
| `native-relay` | No exact match, but many React Native and network-relay near matches | Reject: noisy search results and likely network-relay confusion |
| `framebridge` | Multiple exact GitHub repository matches | Reject |
| `hostscope` | Exact GitHub repository matches | Reject |
| `nativeport` | Case-insensitive exact GitHub repository matches | Reject |

`xvk-data` is removed from subsequent shortlists. Platform capability should
still live in a subtitle, such as “a native data CLI for macOS,” rather than
putting `Mac` or `macOS` back into the product name. Apple's trademark list says
it was updated on 2026-07-14; the current recheck still lists `Mac` and `macOS`
as Apple marks and keeps compatibility wording separate from third-party product names.

## Reusable migration implementation for the 1.0.0 review

After the name is approved:

1. Install one approved canonical command and retain `macos-data` as a symlink
   to the same signed binary for an explicit compatibility period. Do not maintain two
   CLI implementations that can drift.
2. Both invocations share one entry point and produce byte-identical JSON,
   stdout/stderr, and exit codes. Help uses the canonical name and documents the
   compatibility alias.
3. A rename must not silently change the app bundle identifier, TCC identity,
   diagnostics directory, reserved URL label, or `x-macos-data://external-id/`. These are
   persistent identities or data contracts, not ordinary display names.
4. The Homebrew Cask may initially retain its old token while installing both
   `xvk-data` and `macos-data`. Repository/Cask-token migration is a separate
   step so command, TCC, and distribution identities do not all change at once.
5. Add alias contract tests before changing build/install scripts. Cover
   `--version`, `--help`, successful JSON, failed JSON, and exit codes.

Use this migration structure only after the 1.0.0 review or a new ADR explicitly approves another name;
do not default back to `xvk-data`.

## Remaining availability audit

- [x] Check exact Homebrew Formula and Cask names.
- [x] Check exact public GitHub repository names.
- [x] Check the current local executable namespace.
- [x] Generate additional distinctive candidates that contain no Apple marks.
- [x] Check confusingly similar GitHub and Homebrew names, not only exact names.
- [ ] Check relevant trademark registries and obtain legal review if the project
  grows beyond an experimental open-source tool.
- [ ] Check repository, Homebrew Cask, common package registry, and practical
  domain availability for the final shortlist; repository, Cask, npm, and PyPI
  are checked, while crates.io and domains remain unconfirmed.
- [ ] Test pronunciation, spelling, searchability, and command ergonomics with
  humans and Agents.
- [x] Record the 0.x canonical command in an ADR: retain `macos-data` and review before 1.0.0.
- [ ] Design and test alias installation, help/version output, shell completion,
  deprecation messaging, and rollback before changing the public command.
