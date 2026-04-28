#!/usr/bin/env bash
# Run the security regression suite. CI-friendly exit codes.
#
# Origin: TUNE-0045 P1.1 — security baseline scaffold.

set -euo pipefail
IFS=$'\n\t'

cd "$(dirname "$0")/../.."

if ! command -v bats >/dev/null 2>&1; then
  echo "ERROR: bats not installed. Install via 'brew install bats-core' or 'apt-get install -y bats'." >&2
  exit 2
fi

bats tests/security/
