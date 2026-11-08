#!/usr/bin/env bash
set -euo pipefail
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
