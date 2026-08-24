#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
validator=${RESEARCH_AUDIT_SCRIPT:-${repo_root}/dev-tools/check-research-authority-audit.py}

exec python3 "$validator" \
    --expected-task-id TALO-0001 \
    --manifest "${repo_root}/datarim/insights/TALO-0001-research-authority-audit.json" \
    --insights "${repo_root}/datarim/insights/INSIGHTS-TALO-0001.md" \
    "$@"
