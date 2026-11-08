#!/usr/bin/env bash
set -euo pipefail
# Keep this list in step with the constructs named above. A suite that
# covers newly-added portability-sensitive code belongs here too.
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
