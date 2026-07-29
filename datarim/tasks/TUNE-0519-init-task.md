---
task_id: TUNE-0519
artifact: init-task
schema_version: 1
captured_at: 2026-07-29
captured_by: coordinator (enforcement-program)
operator: coordinator
status: canonical
source: enforcement-program-brief
---

# TUNE-0519 — Init-Task

## Operator brief (verbatim)

From `/tmp/enforcement-program-brief.md` § Queue item 2:

TUNE-0519 (P0, L3) — SSH host-key enforcement gate. Convert `execution-host.sh`
from a sourced library into a PreToolUse hook. 6 files carry identical
UNENFORCED P0 dispatch rules (host key MUST match, NEVER run locally, NEVER
dispatch to unverified). The logic exists; the agent can simply skip it.
Highest blast radius in the queue: a violation dispatches work to the wrong
machine. **Caution:** a PreToolUse hook that misfires can block all Bash calls
fleet-wide. Fail-open on hook-internal error, fail-closed only on a genuine
host-key mismatch. Test the failure mode explicitly before merging.

## Append-log (operator amendments)

_(empty at creation)_
