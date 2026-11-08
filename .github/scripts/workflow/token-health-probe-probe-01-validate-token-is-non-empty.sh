#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
if [ -z "${TOKEN:-}" ]; then
  echo "::error::Token secret is empty — repository SECRET 'token' is missing or unset"
  exit 89
fi
