#!/usr/bin/env bash
set -euo pipefail

# Deliberately manual: this benchmark uses only synthetic Mail fixtures and is
# not part of CI or a release gate.
swift test --filter MailStoreTests.testSyntheticMailboxPerformanceBenchmark
