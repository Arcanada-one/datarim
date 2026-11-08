#!/usr/bin/env bash
set -euo pipefail
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA"
