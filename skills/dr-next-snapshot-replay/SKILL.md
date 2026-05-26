---
name: dr-next-snapshot-replay
description: Consumer contract for stage snapshots — /dr-next and /dr-orchestrate read datarim/snapshots/{TASK-ID}.snapshot.md first and emit a replay prompt.
current_aal: 1
target_aal: 2
---

# Stage-Snapshot Replay (consumer side)

`/dr-next` and `/dr-orchestrate`, after Task Resolution, read the snapshot **first** — before task-description, init-task, activeContext, PRD, or plan. If the snapshot exists and is valid, they assemble a replay prompt in the canonical form and continue autonomously. If the snapshot is missing or malformed, fall back to the legacy behaviour without warning noise.

## Contract

| Aspect | Value |
|--------|-------|
| Consumer touchpoints | `commands/dr-next.md` § Step 2.5, `plugins/dr-orchestrate/commands/dr-orchestrate.md` § Snapshot-First Resume |
| Snapshot path | `datarim/snapshots/{TASK-ID}.snapshot.md` |
| Validator | `dev-tools/check-stage-snapshot-on-exit.sh --validate-frontmatter --task <ID>` (exit 0 = ok) |
| Fallback policy | snapshot absent OR validator exit ≠ 0 → legacy Read pipeline, **no warning** (V-AC-7) |
| Prompt template | see § Replay-prompt template below |

## Replay-prompt template (canonical, V-AC-6 + V-AC-11)

When the snapshot is valid, emit exactly this shape, with no improvisation:

<!-- allow-non-ascii-block: canonical-bilingual-replay-prompt-rendered-verbatim-to-agent-runtime -->

```
<recommended-CTA>

ищи способ исследовать все проблемы и ответить на все вопросы самостоятельно. выполняй за оператора все необходимые шаги и требования, которые можешь сделать сам. не создавай FU подзадачи, если они уровня 1, а решай их в этом же цикле до полного решения.
Find a way to investigate all problems and answer all questions yourself. Perform on behalf of the operator every step and requirement you can do yourself. Do not spawn FU sub-tasks for Level-1 work — resolve them in the same cycle to completion.

done before:
<snapshot body>
```

<!-- /allow-non-ascii-block -->

- `<recommended-CTA>` — the `recommended_next` value from the snapshot frontmatter plus one purpose line, expanded by the CTA heuristic below.
- The bilingual block (Russian primary + English duplicate) is mandatory in **every** replay prompt — it guarantees execution regardless of the runtime's locale (Claude Code / Codex CLI / English-locale agents).
- The `done before:` header is a literal; the exact snapshot body content follows underneath.

## CTA Selection heuristic (V-AC-12, natural-language guidance)

The `recommended_next` value from the snapshot is a hint already emitted correctly by the previous stage per `cta-format.md` § Authoring Rules. This heuristic documents the **rationale** for preferring that option; it does not recompute it. If the operator has a reason to pick a different option from `options[]`, the operator types it explicitly — the replay prompt shows the recommended option but does not block an override.

Principle: **maximise the marginal quality improvement of the solution**. For L3+ tasks with few verification passes so far, prefer verification commands (`/dr-verify`, `/dr-qa`, `/dr-design`) over `/dr-do`. When verification is saturated, move on to implementation or archiving.

### Example 1 — L3+ after `/dr-plan`, few verification passes → `/dr-verify`

Snapshot: `recommended_next: /dr-verify`, `options:`
- `/dr-do <TASK-ID> | TDD implementation`
- `/dr-design <TASK-ID> | ratify Vault relativePath`
- `/dr-qa <TASK-ID> | pre-implementation coverage`
- `/dr-verify <TASK-ID> | tri-layer plan verification`
- `/dr-status | escape hatch`

The heuristic picks `/dr-verify` — the plan has just been finalised and the security review / threat model have not yet been cross-checked by an independent layer. Verification is cheaper than rolling back `/dr-do` if drift is found later. Rationale: <TASK-ID> is an L3 security-critical task with 21 V-AC; the cost of a verification verdict (Layer 1 deterministic + Layer 2 cross-model + Layer 3 native dispatch) is far lower than rolling back a bootstrap on PROD.

### Example 2 — L3+ saturated with verification (plan + design + verify done) → `/dr-do`

Snapshot: `recommended_next: /dr-do`, `options:`
- `/dr-do <TASK-ID> | TDD implementation`
- `/dr-qa <TASK-ID> | redo coverage check`
- `/dr-status | escape hatch`

The heuristic picks `/dr-do` directly. Rationale: accumulated evidence (plan + design + tri-layer verify all green) is enough for a confident implementation pass. Another `/dr-qa` is diminishing returns; `/dr-status` is the escape hatch for non-standard operator decisions.

### Example 3 — L1/L2 after `/dr-do` → `/dr-archive`

Snapshot: `recommended_next: /dr-archive`, `options:`
- `/dr-archive <TASK-ID> | finalise + archive doc`
- `/dr-qa <TASK-ID> | optional re-check`
- `/dr-status | escape hatch`

The heuristic picks `/dr-archive`. Rationale: per `cta-format.md` § Authoring Rules, the L1/L2 primary after `/dr-do` is `/dr-archive`. Implementation is already done; archive captures the outcome and frees activeContext. Override only when `/dr-do` surfaced open questions that justify a revisit.

## Implementation outline

```
1. Resolve TASK-ID per Task Resolution Rule.
2. snapshot_path = "$REPO_ROOT/datarim/snapshots/${TASK_ID}.snapshot.md"
3. if check-stage-snapshot-on-exit.sh --validate-frontmatter --task "$TASK_ID" → exit 0:
       read snapshot body + frontmatter
       emit replay prompt per § Replay-prompt template
       STOP downstream Read pipeline — primary context = snapshot
   else:
       silent fallback → legacy Read order (task-description / init-task / activeContext)
```

`/dr-orchestrate` integrates the snapshot-first read **before** `subagent_resolver.sh`; `recommended_next` is passed to the resolver as `--hint <command>`. The resolver may still return a different command — the snapshot is a hint, not a constraint.

## Related

- `skills/stage-snapshot-writer/SKILL.md` — the producer side.
- `skills/cta-format/SKILL.md` — the CTA block format that fills `<recommended-CTA>`.
- `dev-tools/check-stage-snapshot-on-exit.sh` — the mandatory validator that runs before the prompt is emitted.
- `commands/dr-next.md` § Step 2.5 — consumer touchpoint.
- `plugins/dr-orchestrate/commands/dr-orchestrate.md` § Snapshot-First Resume — orchestrator touchpoint.
