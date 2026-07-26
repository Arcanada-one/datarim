---
task_id: TUNE-0498
artifact: init-task
schema_version: 1
captured_at: 2026-07-26
captured_by: /dr-init (auto)
operator: dev
status: canonical
source: /dr-init
---

# TUNE-0498 - Init-Task

## Operator brief
datarim-doctor.sh breaks on macOS bash-3.2 in --scope=all:
1. `tr: Illegal byte sequence` — `head -c 300` splits multibyte UTF-8 char, BSD tr aborts
2. `tok_array[@]: unbound variable` — empty array deref under `set -u`

Fix: LC_ALL=C for both tr calls + guard with ${tok_array[@]:-}. Add bats test.
