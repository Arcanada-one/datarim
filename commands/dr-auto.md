---
name: dr-auto
description: Мета-команда автономного исполнения — активирует FB-1..8 mandate + L1 Inline Resolution Rule + autonomous-ops scope как default-on. Подавляет уточняющие вопросы через 5-уровневую Question Suppression Ladder. Two modes — Continue (resume task) / Bootstrap (full pipeline).
model: opus
runtime: [claude, codex]
current_aal: 2
target_aal: 2
---

# /dr-auto — Autonomous Execution Mode

Активирует существующие mandates FB-1..8 как default-on. Делегирует подавление Q&A в `skills/autonomous-mode/SKILL.md`. Моды: Continue (resume task) / Bootstrap (full pipeline).

**Role**: Adaptive (planner/architect/developer per dispatched stage)
**Activates skill**: `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`

## Instructions

**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as first line per `skills/cta-format/SKILL.md` § Stage Header.

0. **RESOLVE PATH**: Walk-up к `datarim/` per `skills/datarim-system/SKILL.md` § Path Resolution Rule. If not found → STOP, tell operator run `/dr-init`.

1. **MODE DETECTION**:
   - ARGUMENTS matches `^[A-Z]{2,10}-[0-9]{4}$` AND task exists в `datarim/tasks.md` → **Continue mode**.
   - Иначе → **Bootstrap mode** (treat ARGUMENTS как free-text description для последующего `/dr-init`).

2. **ACTIVATE AUTO-MODE**:
   - Export env var: `export DATARIM_AUTO_MODE=1`.
   - Write marker file `datarim/.auto-mode-active` (YAML per `skills/autonomous-mode/SKILL.md` § When this skill is active):
     ```yaml
     task_id: "{TASK-ID}"
     activated_at: "<ISO-timestamp>"
     activated_by: /dr-auto
     mode: continue|bootstrap
     ```
   - Marker MUST be removed at terminal step (success или hard-stop).

3. **LOAD CONTRACT**: Read `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` — Question Suppression Ladder + L1 Inline Resolution Rule + Hard-gated Action Boundary + Failure modes.

4. **DISPATCH**:
   - **Continue mode**: invoke `/dr-next {TASK-ID}` semantics (snapshot-first read), затем resume pipeline from last stage indicated by snapshot.
   - **Bootstrap mode**: sequential stages `/dr-init → /dr-prd (если L3+ или Class B) → /dr-plan → /dr-do → /dr-qa → /dr-compliance → /dr-archive`. После каждой стадии: проверить exit condition.

5. **PER-STAGE SUPPRESSION**: каждая dispatched stage видит `DATARIM_AUTO_MODE=1` + matching marker, применяет `## /dr-auto Mode` block из своего commands/dr-*.md, который ссылается на Question Suppression Ladder в skills/autonomous-mode/SKILL.md. Q&A point reached → consult Ladder L1-L4, escalate to L5 (operator) только если все mute.

6. **L1 INLINE GAP CAPTURE**: gaps discovered mid-pipeline → classify per L1 Inline Rule (decision tree в skills/autonomous-mode/SKILL.md). Inline-resolved gaps append в `datarim/tasks/{TASK-ID}-auto-inline-log.md` с timestamp + files-touched + LoC delta + classification rationale.

7. **OPERATOR ESCALATION (L5)**: hard-gated actions OR Ladder L1-L4 не дали unambiguous answer → AskUserQuestion via standard mechanism. Log через `dev-tools/append-init-task-qa.sh --decided-by operator --stage <current-stage>`.

8. **TERMINAL CLEANUP**: at success / hard-stop:
   - Remove `datarim/.auto-mode-active`.
   - Emit CTA block per `skills/cta-format/SKILL.md` § CTA format.
   - Emit Stage Snapshot per `skills/cta-format/SKILL.md` § Snapshot Emission (`stage: auto`, `command: /dr-auto`).
   - Operator MAY explicitly `unset DATARIM_AUTO_MODE` в shell (otherwise mismatch detection caught on next `/dr-*` run).

## Hard-stops (operator-required even under /dr-auto)

Verbatim из `documentation/mandates/autonomous-agents.md:30-32` — full list в `skills/autonomous-mode/SKILL.md` § Hard-gated Action Boundary. Краткий summary:

- Production deploys (любой prod environment).
- Secret rotation (Vault keys, OAuth tokens, API keys).
- Irreversible DB operations (DROP / TRUNCATE без backup).
- Public communications (Telegram channel posts, blog posts, social media publishes).
- Finance / legal actions.
- Force-push to `main`/`master`.
- Deletion of git history.
- Actions affecting > 1 human user.
- Cross-project boundary writes (repo вне task's project scope per Task Prefix Registry).

## When to use

- **Task с явной scope и operator brief, где Q&A pattern неэффективен** — e.g. backlog items L1-L2 с clear acceptance criteria.
- **Continue interrupted task** — agent crashed mid-cycle, нужно resume с last snapshot.
- **Dogfood и pipeline benchmarks** — measure Q&A suppression rate.

## When NOT to use

- **Exploratory задачи** где operator intent нужно frequently refine.
- **High-stakes Class B** изменения framework operating-model — operator presence нужно для each stage gate.
- **Cross-project orchestration** — используй `/dr-orchestrate` plugin, не `/dr-auto`.

## Args

`/dr-auto {TASK-ID}` — Continue mode (resume).
`/dr-auto "{free-text description}"` — Bootstrap mode (full pipeline from `/dr-init`).

## Next Steps (CTA)

After terminal stage, the agent MUST emit CTA block per `skills/cta-format/SKILL.md`.

**Routing logic for /dr-auto:**
- Terminal stage = `/dr-archive` successful → primary `/dr-status` (review next backlog candidate)
- Hard-stop reached → primary `/dr-do {TASK-ID}` (continue manually) + alternative `/dr-qa {TASK-ID}` (verify state)
- L5 escalation pending answer → primary `/dr-auto {TASK-ID}` (resume after operator answer)
- Always include `/dr-status` as escape hatch

## Stage Snapshot Emission (Mandatory Terminal Step)

After CTA block, emit snapshot per `skills/cta-format/SKILL.md` § Snapshot Emission:
- `stage`: `auto`
- `command`: `/dr-auto`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed)

Fail-closed: non-zero writer exit → single stderr warning, continue. Kill switch `DATARIM_DISABLE_SNAPSHOT=1` makes writer no-op.

## Related

- Skill: `skills/autonomous-mode/SKILL.md` — canonical contract loaded by this command.
- Mandate: `documentation/mandates/autonomous-agents.md` — FB-1..8 rules source-of-truth.
- Sibling commands: `/dr-next` (Continue mode underlying mechanism), `/dr-orchestrate` (parallel multi-task, orthogonal).