#!/usr/bin/env bash
set -euo pipefail
rc=0; bash dev-tools/check-archive-landing.sh --direction sideways || rc=$?
[ "$rc" -eq 2 ] || { echo "expected usage error 2, got $rc"; exit 1; }
rc=0; bash dev-tools/check-archive-landing.sh --ref no/such/ref --direction a || rc=$?
[ "$rc" -eq 3 ] || { echo "expected refusal 3, got $rc"; exit 1; }
