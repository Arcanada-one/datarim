---
name: session-handoff-replay
description: Consumer contract for session-handoff artefacts — /dr-continue reads datarim/sessions/{SESSION-ID}.session.md first and re-verifies every claim before routing to /dr-next or /dr-auto.
current_aal: 1
target_aal: 2
---

# Session-Handoff Replay (consumer side)

`/dr-continue` reads the session artefact **first** — before task-description,
activeContext, PRD, or plan — and re-grounds every claim with a live probe.
The consumer never trusts the snapshot; it re-verifies everything.

**The prior session WAS DESTROYED.** When this skill is active, treat all
claims in the artefact as unverified until re-probed.

## Contract

| Aspect | Value |
|--------|-------|
| Consumer touchpoints | `commands/dr-continue.md` |
| Artefact path | `datarim/sessions/{SESSION-ID}.session.md` (latest file by mtime when no explicit ID given) |
| Validator | `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-session-handoff.sh" --validate-frontmatter --session <ID>` (exit 0 = ok) |
| Fallback policy | artefact absent OR validator exit ≠ 0 → inform the operator, do NOT silently proceed |
| Replay template | See § Replay-prompt template below (shared renderer, per `skills/dr-next-snapshot-replay/SKILL.md` § Shared Replay Renderer) |

## Re-verification protocol (STRICT — do not skip)

Every claim in the artefact is treated as unverified until re-probed. The
consumer MUST execute the following probes before rendering the replay prompt.
The banner strings (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING) are
emitted by the deterministic core `dev-tools/reverify-session-claims.sh` — the
consumer invokes it once per claim/repo/file rather than hand-rendering the
wording, so the safety property is deterministic and regression-tested. The
prose below describes the underlying probe; the emitter is the canonical source
of the banner text.

**Probe 1 — Git state (STALE SNAPSHOT check)**

For every repo listed in Layer 1:
```bash
git -C <repo> rev-parse HEAD
git -C <repo> status --porcelain
```
Compare to saved HEAD SHA and status. If different → emit banner:

```
STALE SNAPSHOT: <repo> HEAD changed from <saved-sha> to <current-sha>
```

**Probe 2 — Pushed/merged claims (CLAIM-UNVERIFIED check)**

For every line tagged `verified:` containing `pushed` or `merged`:
```bash
git -C <repo> cherry -v origin/main <saved-sha>
```
If the SHA is absent from `origin/main` (not in diff, not in ancestry), emit:

```
CLAIM-UNVERIFIED: SHA <sha> not found in origin/main.
Content-landing check: git diff <saved-sha> origin/main -- <files>
(empty diff = work landed under a different squash-commit header)
```

The squash-collision case (content landed under a foreign squash-commit) MUST
be surfaced explicitly so the agent does not falsely conclude work was lost.

**Probe 3 — Referenced files (FILE-MISSING check)**

For every path in Layer 3:
```bash
stat <path>
```
If missing → emit:

```
FILE-MISSING: <path> — may have moved, merged, or been deleted.
```

**Provenance downgrade rule**

Any claim tagged `verified:` in the artefact is downgraded to `unverified` in
the replay output unless the current probe confirms it. Only after a passing
probe does the replay carry `verified:`.

## Replay-prompt template

This template is the **shared renderer** defined in
`skills/dr-next-snapshot-replay/SKILL.md` § Shared Replay Renderer.

The session-handoff replay emits the same bilingual block and `done before:`
structure as the per-task snapshot replay, with these additions:

1. Re-verification banners (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING)
   emitted BEFORE the bilingual block.
2. `<recommended-CTA>` from the artefact's `recommended_next` frontmatter field.

<!-- allow-non-ascii-block: canonical-bilingual-replay-prompt-rendered-verbatim-to-agent-runtime -->

```
[STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING banners, if any]

<recommended-CTA>

ищи способ исследовать все проблемы и ответить на все вопросы самостоятельно. выполняй за оператора все необходимые шаги и требования, которые можешь сделать сам. не создавай FU подзадачи, если они уровня 1, а решай их в этом же цикле до полного решения.
Find a way to investigate all problems and answer all questions yourself. Perform on behalf of the operator every step and requirement you can do yourself. Do not spawn FU sub-tasks for Level-1 work — resolve them in the same cycle to completion.

done before:
<artefact body — with downgraded provenance tags applied>
```

<!-- /allow-non-ascii-block -->

## TASK-ID resolution in a clean window

In a clean window the consumer has no conversation history to resolve the
current TASK-ID. Apply the Task Resolution Rule:

1. Read `datarim/tasks.md` — list active tasks.
2. If exactly one active task → use it.
3. If zero active tasks → inform the operator; the session may be stale.
4. If >1 active tasks → show the list and ask the operator which to resume,
   or accept `/dr-continue {TASK-ID}` as an explicit override.

## Implementation outline

```
1. Locate latest session artefact:
   latest = newest file in datarim/sessions/*.session.md by mtime
   (or use the explicit SESSION-ID / TASK-ID provided by the operator)

2. Validate: check-session-handoff.sh --validate-frontmatter --session <ID>
   exit 0 → proceed
   exit ≠ 0 → inform operator (do NOT silently fall through)

3. Run Probe 1 (git state per repo in Layer 1) → collect STALE banners
4. Run Probe 2 (pushed/merged SHA-presence) → collect CLAIM-UNVERIFIED banners
5. Run Probe 3 (re-stat Layer-3 files) → collect FILE-MISSING banners

6. Emit re-verification banners (if any).

7. Resolve TASK-ID (Task Resolution Rule above).

8. Emit replay prompt per § Replay-prompt template with downgraded provenance.

9. Route: head-of-queue task → /dr-next {TASK-ID} or /dr-auto {TASK-ID}.
```

## Related

- `skills/session-handoff-writer/SKILL.md` — the producer side.
- `skills/dr-next-snapshot-replay/SKILL.md` § Shared Replay Renderer — bilingual template source.
- `dev-tools/check-session-handoff.sh` — the mandatory validator.
- `dev-tools/reverify-session-claims.sh` — deterministic re-verification banner emitter (the canonical source of the STALE / CLAIM-UNVERIFIED / FILE-MISSING / CONTENT-LANDED strings).
- `commands/dr-continue.md` — the operator-facing command.
- `commands/dr-next.md` — routes for per-task resume after session replay.
