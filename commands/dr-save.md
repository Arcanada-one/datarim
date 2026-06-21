# /dr-save — Save Session Handoff

**Stage:** Session Handoff (producer)
**Agent:** developer (or current active agent)
**Skill:** `skills/session-handoff-writer/SKILL.md`

---

## Purpose

`/dr-save` captures the current session state to disk before the context
window is destroyed. It writes a self-contained markdown artefact to
`datarim/sessions/SESSION-{YYYYMMDD-HHMMSS}.session.md` that a future
`/dr-continue` can read in a clean window to restore context.

Use `/dr-save` when:
- About to close the terminal or reset the agent context.
- Switching machines or runtimes.
- Before a long break where the context will time out.
- When another agent will pick up this session.

## Instructions

### Step 1 — Load the producer skill

Read `${DATARIM_RUNTIME:-$HOME/.claude}/skills/session-handoff-writer/SKILL.md`
and apply the producer-awareness clause: the session WILL be destroyed.
Capture everything needed to resume from zero.

### Step 2 — Collect 5-layer body content

Compose the body file with the 5-layer structure:

**Layer 1 — Git State (PROTECTED — non-truncatable)**
For every repo touched this session, run `git rev-parse HEAD`, `git status --porcelain`,
`git log -3 --oneline`. Record results verbatim (no truncation — this layer is
protected). Include the repo absolute path, HEAD SHA, branch name, and dirty/clean status.

**Layer 2 — Active Tasks**
For each active task: read `datarim/snapshots/{TASK-ID}.snapshot.md` (if present)
and copy its body. Add the current status, last completed stage, and next step.
Tag every claim: `verified:` (you can confirm it now) or `assumed:` (you believe
it but cannot confirm without a probe).

**Layer 3 — Related Files**
List every file read or modified this session with a one-line status note.

**Layer 4 — Open Questions**
Cross-task questions not resolved. One sentence each. Tag: `verified:` or `assumed:`.

**Layer 5 — Failed Approaches (PROTECTED — non-truncatable)**
Every approach tried and abandoned, with the reason it failed. Be specific —
"tried X, failed because Y" — so the resume session does not repeat the same error.

**Raw tool output MUST NOT appear** in any layer — summarise instead.

### Step 3 — Tag every claim

Before writing, scan the body for lines containing `pushed`, `merged`, `deployed`,
`green`, or `passing`. Every such line MUST carry a `verified:` or `assumed:` tag
on the same line. The writer will reject (exit 1) any untagged claim.

### Step 4 — Invoke the writer

Generate a session ID and call the wrapper:

```bash
SESSION_ID="SESSION-$(date -u +%Y%m%d-%H%M%S)"
REPO_ROOT="$(git -C . rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/session-handoff-writer-wrapper.sh" \
    --root "${REPO_ROOT}" \
    --session "${SESSION_ID}" \
    --captured-by agent \
    --recommended-next "<next-command>" \
    --next-action "<single-line description of what to do on resume>" \
    --active-tasks-file "${REPO_ROOT}/datarim/tasks.md" \
    --body-file "<path-to-body-file>"
```

Check the exit code. If non-zero, report the error to the operator — do NOT
silently continue, and do NOT hand-author the artefact.

### Step 5 — Emit the resume block

After a successful write, print:

```
Session saved → datarim/sessions/{SESSION-ID}.session.md

To resume in a fresh window, copy this line exactly:

  /dr-continue {SESSION-ID}

  ↳ {TASK-ID} — {title}   (saved {human-date-from-SESSION-ID} UTC)
    Next: {next-action}
    Also active this session: {other-task-ids}

{SESSION-ID} is the only argument that selects this saved session — a bare
/dr-continue may grab another agent's session in a shared workspace. The
task name and date are labels for you, not command input.

Do NOT use claude --continue / codex resume / Cursor chat history.
A fresh session + /dr-continue is the only safe resume path.
```

## /dr-auto Mode (when DATARIM_AUTO_MODE=1)

When auto-mode is active (env var + matching marker), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`
   § Question Suppression Ladder before any operator prompt.
2. Applies L1-resolution for the current task's git state (git rev-parse + status
   are deterministic probes — no question needed).
3. Tags all claims `verified:` when the supporting probe is run inline; uses
   `assumed:` for claims from earlier in the session that are not re-probed.
4. Hard-gated: the write itself is NOT hard-gated (it is a local file write, not
   a production deploy, public action, or irreversible operation). Proceeds automatically.

## Validation

After writing, run:

```bash
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-session-handoff.sh" \
    --validate-frontmatter \
    --session "${SESSION_ID}" \
    --root "${REPO_ROOT}"
```

Exit 0 = artefact valid. Any other exit = do NOT claim the save succeeded.

## Related

- `skills/session-handoff-writer/SKILL.md` — full producer contract.
- `commands/dr-continue.md` — the consumer command that reads the artefact.
- `dev-tools/session-handoff-writer-wrapper.sh` — the entry point.
- `dev-tools/check-session-handoff.sh` — the validator.
