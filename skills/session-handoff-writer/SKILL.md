---
name: session-handoff-writer
description: Producer contract for session-handoff artefacts — /dr-save writes datarim/sessions/{SESSION-ID}.session.md before the session is destroyed.
current_aal: 1
target_aal: 2
---

# Session-Handoff Writer (producer side)

`/dr-save` writes a self-contained session artefact while the live context is
still in-window. The command is invoked when the operator signals the session
will be destroyed — the agent must capture everything needed to resume from
zero in a clean window.

## Producer-Awareness Clause

**The session will be destroyed.** When this skill is active, the agent must
assume the current context window will not survive. Every claim, observation,
and pending action must be captured in the artefact. The agent cannot rely on
the operator typing a summary — the artefact IS the handoff.

Corollary: every claim-keyword line (`pushed`, `merged`, `deployed`, `green`,
`passing`) MUST carry a `verified:` or `assumed:` provenance tag on the same
line. The writer rejects untagged claims with exit 1. This is the safety gate
that prevents a stale snapshot from misleading a resume session.

## Contract

| Aspect | Value |
|--------|-------|
| Entry point | `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/session-handoff-writer-wrapper.sh"` (never `sh`) |
| Artefact path | `datarim/sessions/SESSION-{YYYYMMDD-HHMMSS}.session.md` |
| Semantics | Append-only decision-log — a second `/dr-save` in the same session APPENDS a new dated block, never truncates prior blocks |
| Lock | `datarim/sessions/.lock.{SESSION-ID}` (mkdir-based atomic, POSIX-portable) |
| Cap | 32768 bytes total; Layer-1 (git state) and Layer-5 (failed approaches) blocks are protected from truncation; Layer-3/4 truncated first |
| Permissions | artefact `chmod 600`, directory `chmod 700` |
| Kill-switch | `DATARIM_DISABLE_SESSION_HANDOFF=1` — no-op, exit 0, no file written |
| Security | T-1 session-id regex validation; T-2 `--body-file` (no shell expansion); T-3 mkdir lock; T-5 chmod 600 + gitignore; T-7 symlink pre-unlink; T-8 secret scan-and-redact |

## Inputs (flags forwarded to the wrapper)

| Flag | Required | Description |
|------|----------|-------------|
| `--root <path>` | yes | Repo root (parent of `datarim/`) |
| `--session <SESSION-YYYYMMDD-HHMMSS>` | yes | Session identifier — must match `^SESSION-[0-9]{8}-[0-9]{6}$` |
| `--captured-by <agent\|operator>` | yes | Who triggered the save |
| `--recommended-next <command>` | yes | CTA for the resume session (e.g. `/dr-next TASK-ID`) |
| `--next-action <description>` | yes | Single-line summary of what to do on resume |
| `--active-tasks-file <path>` | yes | File listing active tasks (one per line, `TASK-ID \| status`) |
| `--body-file <path>` | yes | Path to the 5-layer body content (see § Body layers below) |
| `--captured-at <ISO 8601 UTC>` | no | Override timestamp (defaults to `date -u`) |

## Body layers (5-layer structure)

The body passed via `--body-file` MUST follow the 5-layer structure:

```
## Layer 1 — Git State

For every repo touched this session: HEAD SHA, branch, status --porcelain output.
Non-truncatable — this layer is protected from cap truncation.

## Layer 2 — Active Tasks

Reuse the body from datarim/snapshots/{TASK-ID}.snapshot.md where present.
One block per active task: current status, last stage completed, next step.

## Layer 3 — Related Files

Paths of every file read or modified this session, with a one-line status note.

## Layer 4 — Open Questions

Cross-task questions not resolved this session. Tag each: verified: or assumed:.

## Layer 5 — Failed Approaches

Every approach tried and abandoned this session, with the reason it failed.
Non-truncatable — this layer is protected from cap truncation.
```

Raw tool output (curl responses, full stack traces, git log dumps) MUST NOT
appear in any layer — summarise instead. This keeps the artefact within the
32 KB cap and readable on resume.

## Fail-closed contract

If the writer exits non-zero, the agent MUST emit a visible error message to
the operator. Do NOT silently continue — the operator needs to know the
handoff failed. Never hand-author the artefact to work around a writer error;
instead, fix the underlying cause (claim-provenance tag, session-id format,
root path) and re-run.

## Security cross-link

Full threat model in the task-description Appendix A (T-1 through T-8).
Key points:
- T-8 (secret scan-and-redact): the writer scans the body for common API key /
  credential patterns (AWS `AKIA*`, PEM headers, `ghp_*`, `sk-*` prefixes,
  `client_secret_*`) and replaces matches with `[REDACTED]`. This protects
  against accidentally capturing a token pasted into a diff or error message.
- T-7 (symlink): the writer pre-unlinks any symlink at the target path before
  the atomic rename, preventing a symlink-swap attack between check and write.

## Invocation example (literal — copy verbatim)

```bash
SESSION_ID="SESSION-$(date -u +%Y%m%d-%H%M%S)"
BODY_FILE="$(mktemp)"
# ... populate $BODY_FILE with the 5-layer body ...

bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/session-handoff-writer-wrapper.sh" \
    --root "${REPO_ROOT:-$PWD}" \
    --session "${SESSION_ID}" \
    --captured-by agent \
    --recommended-next "/dr-next ${TASK_ID}" \
    --next-action "Continue Phase P2 — implement X." \
    --active-tasks-file "${TASKS_FILE}" \
    --body-file "${BODY_FILE}"
rc=$?
rm -f "${BODY_FILE}"
if [ "$rc" -ne 0 ]; then
    printf 'ERROR: session-handoff write failed (exit %d). Session not persisted.\n' "$rc"
fi
```

## Resume block (emit after every successful /dr-save)

After a successful write, the agent MUST print the following block visibly:

```
Session artefact written: datarim/sessions/{SESSION-ID}.session.md

To resume in a clean window:
  /dr-continue

Do NOT use claude --continue / codex resume / Cursor chat history.
Those rehydrate a stale context. A fresh session + /dr-continue is the
only safe resume path.
```

## Related

- `skills/session-handoff-replay/SKILL.md` — the consumer side.
- `skills/dr-next-snapshot-replay/SKILL.md` § Shared Replay Renderer — bilingual replay template cited by the consumer.
- `dev-tools/check-session-handoff.sh` — the validator (run on consumer side before replay).
- `dev-tools/session-handoff-writer-wrapper.sh` — the entry-point wrapper.
- `scripts/lib/session-handoff-writer.sh` — the implementation.
- `commands/dr-save.md` — the operator-facing command that invokes this skill.
