# CLI naming and compatibility audit

Status: initial candidate inventory and exact-name audit completed on 2026-07-23.
No rename has been approved.

## Adopted transition constraints

- The 0.2.x line continues to use `macos-data`.
- Version 0.3.x may introduce a trademark-neutral canonical command.
- `macos-data` remains a documented compatibility alias through at least the
  complete 0.3.x line.
- Old and new command names must produce identical JSON, stdout/stderr routing,
  and exit codes.
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

## Remaining availability audit

- [x] Check exact Homebrew Formula and Cask names.
- [x] Check exact public GitHub repository names.
- [x] Check the current local executable namespace.
- [ ] Generate additional distinctive candidates that contain no Apple marks.
- [ ] Check confusingly similar GitHub and Homebrew names, not only exact names.
- [ ] Check relevant trademark registries and obtain legal review if the project
  grows beyond an experimental open-source tool.
- [ ] Check repository, Homebrew Cask, common package registry, and practical
  domain availability for the final shortlist.
- [ ] Test pronunciation, spelling, searchability, and command ergonomics with
  humans and Agents.
- [ ] Approve one canonical name and record the decision in an ADR.
- [ ] Design and test alias installation, help/version output, shell completion,
  deprecation messaging, and rollback before changing the public command.

