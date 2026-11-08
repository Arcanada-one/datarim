#!/usr/bin/env bash
set -euo pipefail
for target in \
  skills \
  agents \
  commands \
  templates \
  dev-tools/rules \
  documentation/how-to \
  documentation/reference \
  documentation/explanation \
  documentation/tutorials \
  AGENTS.md \
  README.md; do
  bash scripts/task-id-gate.sh "$target"
done
