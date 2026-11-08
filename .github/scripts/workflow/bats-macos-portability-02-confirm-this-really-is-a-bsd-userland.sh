#!/usr/bin/env bash
set -euo pipefail
if head -c 0 /dev/null 2>/dev/null; then
  echo "::error::head -c 0 succeeded — this is GNU coreutils, not BSD."
  echo "This job's whole purpose is BSD coverage; passing here would be false assurance."
  exit 1
fi
echo "BSD userland confirmed (head -c 0 rejected, as expected)."
