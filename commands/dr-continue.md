# /dr-continue — Resume from Session Handoff

**Stage:** Session Handoff (consumer)
**Agent:** developer (or current active agent)
**Skill:** `skills/session-handoff-replay/SKILL.md`

---

## Purpose

`/dr-continue` reads the session artefact written by `/dr-save` in a
**clean context window** and rehydrates the session. It re-verifies every
claim before presenting the replay prompt, then routes to `/dr-next` or
`/dr-auto` for the head-of-queue task.

**The prior session WAS DESTROYED.** Do not assume any in-memory context.
Read the artefact, re-probe everything, then resume.

Usage:
- `/dr-continue` — reads the latest `datarim/sessions/*.session.md` by mtime.
- `/dr-continue {SESSION-ID}` — reads a specific session artefact.
- `/dr-continue {TASK-ID}` — resolves the session associated with TASK-ID.

## Instructions

### Step 1 — Load the consumer skill

Read `${DATARIM_RUNTIME:-$HOME/.claude}/skills/session-handoff-replay/SKILL.md`.
Apply the consumer-awareness clause: the prior session was destroyed; treat
all claims as unverified until re-probed.

### Step 2 — Locate the session artefact

```bash
SESSIONS_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/datarim/sessions"

# Latest artefact (when no explicit ID given):
ARTEFACT="$(ls -t "${SESSIONS_DIR}/"*.session.md 2>/dev/null | head -1)"

if [ -z "$ARTEFACT" ]; then
    echo "No session artefact found in ${SESSIONS_DIR}/"
    echo "Run /dr-save first to create one."
    exit 1
fi
SESSION_ID="$(basename "$ARTEFACT" .session.md)"
```

### Step 3 — Validate the artefact

```bash
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-session-handoff.sh" \
    --validate-frontmatter \
    --session "${SESSION_ID}"
```

If exit ≠ 0, inform the operator and stop. Do NOT silently fall through to
legacy behaviour — a corrupt or missing artefact requires operator attention.
Validation is best-effort in sandbox environments; if the validator is
unreachable due to time limits, proceed on a readable artefact (log a warning).

### Step 4 — Re-verify claims (STRICT — do not skip)

Read the artefact. For every repo in Layer 1:

```bash
git -C <repo> rev-parse HEAD
git -C <repo> status --porcelain
```

For every `verified: pushed/merged` claim, run the SHA-presence check:

```bash
git -C <repo> cherry -v origin/main <saved-sha> 2>/dev/null
```

For every path in Layer 3:

```bash
stat <path> 2>/dev/null || echo "FILE-MISSING: <path>"
```

Emit the banners through the deterministic emitter (one call per claim/repo/file)
so the "report claim as unverified" property is deterministic, not free-prose:

```bash
EMITTER="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reverify-session-claims.sh"
bash "$EMITTER" --sha-presence --repo <repo> --sha <saved-sha> --files <files…>
bash "$EMITTER" --stale        --repo <repo> --saved-sha <saved-sha>
bash "$EMITTER" --file-missing --path <path>
```

Each call prints the banner string when the claim fails (and the `CONTENT-LANDED`
evidence line for the squash-collision case) and nothing when it holds.
Collect all banners (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING).
Downgrade `verified:` → `unverified` for any claim the probe did not confirm.

### Step 5 — Resolve TASK-ID

If the artefact `active_tasks` list has exactly one entry, use it.
If >1 active tasks are listed: show the list and ask the operator which to
resume (or accept `/dr-continue {TASK-ID}` as override).
If zero active tasks: inform the operator — the artefact may be stale.

### Step 6 — Emit replay prompt

Emit re-verification banners (if any), then the bilingual replay prompt per
`skills/session-handoff-replay/SKILL.md` § Replay-prompt template.

### Step 7 — Route

Route to `/dr-next {TASK-ID}` or `/dr-auto {TASK-ID}` for the head-of-queue
task. The `recommended_next` field in the artefact frontmatter is the hint;
the operator can override.

## /dr-auto Mode (when DATARIM_AUTO_MODE=1)

When auto-mode is active (env var + matching marker), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`
   § Question Suppression Ladder before any operator prompt.
2. Resolves TASK-ID via L1 (read `datarim/tasks.md`) — no question needed for
   single-task sessions.
3. Runs all re-verification probes autonomously (git probes are L2 runtime probes).
4. For TASK-ID ambiguity with >1 active tasks → L5 (operator ask, per Ladder).
5. Routes to `/dr-auto {TASK-ID}` for autonomous continuation.

## Related

- `skills/session-handoff-replay/SKILL.md` — full consumer contract + re-verification protocol.
- `commands/dr-save.md` — the producer command.
- `commands/dr-next.md` — per-task resume after session replay.
- `dev-tools/check-session-handoff.sh` — the validator.
- `dev-tools/reverify-session-claims.sh` — deterministic re-verification banner emitter (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING).
