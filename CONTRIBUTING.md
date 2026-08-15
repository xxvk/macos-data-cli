# Contributing to mpia-cli

Thanks for helping improve `mpia-cli`. Contributions should preserve its
local-first design, stable JSON contracts, and fail-closed safety boundaries.

## Before you start

- Search existing issues before opening a new one.
- Use an issue for behavior changes or new adapters so scope and safety rules
  can be agreed before implementation.
- Never include real contact, message, event, reminder, photo, or note content
  in an issue, test fixture, log, screenshot, or pull request.
- Keep public-framework and documented Automation boundaries explicit. Do not
  introduce private framework or private-store access.

## Development workflow

1. Fork the repository and create a focused branch.
2. Add a failing test for the intended behavior or regression.
3. Implement the smallest compatible change.
4. Update the English and Chinese documentation when a public contract changes.
5. Run the relevant local checks.

The baseline checks are:

```bash
bash scripts/run_swift_tests.sh
swift build
bash scripts/run_cli_contract_tests.sh --no-apply
git diff --check
```

Live macOS integration gates are intentionally separate. Do not run a gate that
writes disposable data unless its documentation requires it and the current
operator has explicitly authorized that write.

## Pull requests

Describe the problem, the user-visible change, affected safety boundaries, and
the checks you ran. Call out contract or compatibility changes explicitly.
Pull requests should not contain unrelated formatting or generated artifacts.

By contributing, you agree that your contribution is licensed under the
repository's MIT License.
