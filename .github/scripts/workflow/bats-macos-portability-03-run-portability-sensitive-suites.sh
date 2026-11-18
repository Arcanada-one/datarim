#!/usr/bin/env bash
set -euo pipefail
# Inventory of portability-sensitive suites (GNU vs BSD constructs).
# CI does not invoke this script: macOS/BSD coverage is NOT_MEASURED (no
# GitHub-hosted runners; no macOS self-hosted runner in the fleet). Keep the
# list current so source review still knows which suites need a BSD userland.
bats \
  tests/stage-snapshot-size-cap.bats \
  tests/stage-snapshot-e2e.bats \
  tests/stage-snapshot-id-regex.bats \
  tests/stage-snapshot-flock-race.bats \
  tests/session-handoff-writer.bats \
  tests/session-sensitive-source-cap.bats \
  tests/customer-requirement-expectations-binding.bats \
  dev-tools/tests/check-archive-landing.bats \
  cli/tests/backlog.bats \
  cli/tests/backlog-add-collision.bats
