# GitHub CLI Environment Know-how

## Purpose

Use this procedure when `gh` behaves differently in Codex, Terminal, or a
non-interactive shell. It performs environment and authentication checks only;
it never logs in automatically and never stores a token in the repository.

## Diagnostic order

```bash
command -v gh
gh --version
gh auth status -h github.com
gh api user --jq .login
```

If `gh` is not found, the non-interactive zsh used by Codex may not load
`~/.zprofile`. On Apple Silicon, Homebrew normally lives under
`/opt/homebrew/bin`; add this to `~/.zshenv` if appropriate:

```zsh
if [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
```

Restart the terminal or Codex process and verify that `command -v gh` returns
`/opt/homebrew/bin/gh`.

If `gh` is found but `gh auth status` or `gh api user` fails, do not immediately
re-login. First distinguish blocked access to `api.github.com`, inability of the
current process to read the macOS Keychain credential, and different permission
environments between Terminal/Ghostty and Codex. Repeat the read-only checks in
an approved network environment. Only if that environment still reports an
invalid token should `gh auth login` be used.

Never put a GitHub token in Markdown, `.zshenv`, repository files, or diagnostic
logs.

The release prerequisite script is read-only with respect to GitHub:

```bash
bash scripts/check_public_release_prerequisites.sh
```

It reports CLI authentication status without printing tokens, logging in, or
creating a Release. A network failure must be recorded as “remote state could
not be verified,” not as proof that the token is invalid.

## Local verification record

Verified on 2026-07-23 in an approved network environment:

- `gh`: `/opt/homebrew/bin/gh`
- version: `2.93.0`
- `gh auth status -h github.com`: logged in as `xxvk`
- `gh api user --jq .login`: `xxvk`

This is an observation of that environment, not a permanent guarantee about
future credentials or remote release state.
