#!/usr/bin/env bash
set -euo pipefail
trufflehog filesystem . --only-verified --fail --no-update
