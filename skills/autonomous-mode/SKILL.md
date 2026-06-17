---
name: autonomous-mode
description: Question Suppression Ladder + L1 Inline Resolution Rule + Hard-gated Action Boundary. Activated via DATARIM_AUTO_MODE=1 + .auto-mode-active marker.
model: inherit
current_aal: 2
target_aal: 2
---

# Autonomous Mode — Question Suppression + L1 Inline + Hard-gated Boundary

This skill activates the existing mandates (`documentation/mandates/autonomous-agents.md` FB-1..8 ([definition](../autonomous-mode/SKILL.md)) — eight Feedback Behaviour rules that define how an autonomous agent answers its own questions; `feedback_l1_proposals_close_in_cycle`; `feedback_autonomous_ops`) as **default-on** inside an active `/dr-auto` cycle. It introduces no new rules — it only changes the default from "conditional activation" to "always on while the mode is active".

## When this skill is active

The skill is active if and only if **all three conditions** hold:

1. `DATARIM_AUTO_MODE=1` is set in the agent's environment.
2. The file marker `datarim/.auto-mode-active` exists and parses as YAML.
3. The `task_id` field inside that marker matches the current TASK-ID (regex `^[A-Z]{2,10}-[0-9]{4}$`).

**Spawned subagents (relaxed activation).** A subagent dispatched by `/dr-auto` does NOT inherit the `DATARIM_AUTO_MODE` environment variable (the Agent tool does not propagate the parent environment). For such a subagent the skill is active when its dispatch prompt carries an explicit auto-signal (a line naming the current stage and "autonomous mode for `<TASK-ID>`") AND conditions 2 and 3 hold (the marker file exists, parses, and its `task_id` matches the current TASK-ID). The environment variable (condition 1) is NOT required in this branch. The top-level `/dr-auto` cycle still requires all three conditions. The auto-signal only removes the env-var requirement — it never substitutes for a missing or mismatched marker file.

**Mismatch** (the env var is set but the marker is missing OR the marker holds a different TASK-ID) → emit one warning line: `auto-mode: DATARIM_AUTO_MODE=1 but marker absent/mismatch — treat as non-auto (fail-safe)`. Continue as if the mode were off.

**Marker file structure** (`datarim/.auto-mode-active`):
```yaml
task_id: TUNE-XXXX
activated_at: 2026-05-24T12:00:00Z
activated_by: /dr-auto
mode: continue|bootstrap
```

**24h TTL.** If the marker was created more than 24 hours ago → silently purge it (the agent deletes the file or ignores it). Only `/dr-auto` re-creates the marker.

## Question Suppression Ladder ([definition](../autonomous-mode/SKILL.md))

Before every `AskUserQuestion` call (or any equivalent operator prompt — phrases like "What do you think?" or "Which option should we pick?") the agent **MUST** walk levels L1 → L4 in order. Stop at the **first** level that returns an **unambiguous** answer. Only if L1-L4 all fail to give one → escalate to L5 (the operator).

| L | Source | When it applies | Cost | Failure mode → escalate to |
|---|--------|-----------------|------|----------------------------|
| 1 | **Codebase grep / file read** | Technical question about the current code, config, schema, versions, dependencies, project layout | <1s | More than one plausible candidate with no tie-breaker → L2 |
| 2 | **Runtime probe** (`curl localhost:3200/healthz`, `docker ps`, `git log -1`, `gh run list`, `vault kv get`, `kubectl get pods`) | State of a service, database, network, CI, deployed secrets, container health | <5s | Probe failed / no signal / timeout → L3 |
| 3 | **MEMORY.md feedback lookup** | Operator preferences, prior decisions, gotchas, policy — `grep -r feedback_` over `MEMORY.md` | <2s | No match or contradictory matches → L4 |
| 4 | **Coworker delegation** (`coworker ask --paths <list> --question "<question>"` — offload bulk I/O to an external LLM to save Claude tokens; see `documentation/infrastructure/Coworker.md`) | Bulk-context lookup: docs across repos, multiple large files, external-LLM reasoning over >10k tokens | <30s | External LLM does not give an unambiguous answer (or says "unknown") → L5 |
| 5 | **Operator ask** (`AskUserQuestion`) | True ambiguity, hard-gated bypass, business strategy | a minute+ | Operator answer is the source of truth; log via `append-init-task-qa.sh --decided-by operator` |

### Pre-resolved decisions (never an operator ask)

Some recurring decisions are pre-resolved by policy and MUST NOT be surfaced as an
`AskUserQuestion`, even when the agent feels uncertain. Treat these as L1-decided:

- **Test on the test environment before prod / archive.** If the project space has a
  test environment (per [[test-env-verification]] resolution chain), the answer to
  "should I deploy to test and verify backend + frontend before preparing for prod or
  archiving?" is always **yes** — do it autonomously. Asking the operator "did we test
  on the test env?" each task is the exact anti-pattern this rule removes. The only
  related escalation permitted is a billable/destructive external action on the test
  env with no safe-mode (`dry_run` / read-only / content-only) equivalent — that
  hits the Hard-gated Action Boundary below.

### Ambiguity definition

Two or more plausible candidate answers at the **same level** with no deterministic tie-breaker (for example, two `package.json` files with different `version` fields) → **escalate to the next level**. If a tie-breaker is possible (for example, grep against an explicit path instead of a wildcard) — apply the tie-breaker; do not escalate.

### Business-strategy questions (narrow mode)

Questions that require business knowledge go **directly to L5**, with no L1-L4 attempt:

- "Do we sell X on market Y?"
- "Who is the paying customer for this feature?"
- "What is our pricing policy for the legacy tier?"
- "What is the legal stance on GDPR compliance for this DPA?"
- Any question where the answer reflects operator intent, not a codebase or runtime fact.

Do not invent a safe default. A future flag "assumed default — confirm at archive" is a separate follow-up after at least three dogfood cycles. Wide-mode operation is an optional separate backlog item and is not part of the current contract.

## L1 Inline Resolution Rule ([definition](../autonomous-mode/SKILL.md))

This rule applies across **every** stage of a `/dr-auto` cycle: `init`, `prd`, `plan`, `do`, `qa`, `compliance`, `archive` — not only the `/dr-archive` reflection step.

### Decision tree

```
discovered gap / improvement opportunity mid-cycle
  ↓
classify by scope (a), contract impact (b), hard-gated check (c):

  (a) scope of change:
      - single file edit       → check (b)
      - multi-file              → L2+, backlog

  (b) contract impact:
      - <=50 LoC, no API/schema/contract/mandate change → L1 Class A
      - API schema change / operating-model shift / PRD change → L2+ or Class B, backlog

  (c) hard-gated check (overrides a+b):
      - matches autonomous-agents.md:30-32 list  → HARD, always operator-escalate
      - cross-project boundary (repo outside task's project scope) → HARD
      - neither → proceed with (a) → (b) classification

  resolution:
      L1 Class A → fix INLINE within the current /dr-do scope; log to auto-inline-log.md
      L2+ or Class B → create a backlog item with Source: discovered-during-auto-{TASK-ID}
      HARD → emit an operator prompt via Ladder L5; do not auto-execute
```

### Inline-log contract

File: `datarim/tasks/{TASK-ID}-auto-inline-log.md` — append-only, populated during `/dr-do`. Each entry:

```markdown
### <ISO-ts> · inline-gap-resolved

- **What:** <one-line description of the gap>
- **Files touched:** <list of file paths>
- **LoC delta:** <±N total>
- **Classification rationale:** <why L1 + Class A: single file, <=50 LoC, no contract change, not hard-gated>
```

Consumed by `/dr-archive` Step 0.5 (pre-reflection): the inline-log surfaces as an "Inline-resolved gaps" section in the archive document. If archive Step 0.5 finds unresolved entries → warning: "N inline gaps not logged in auto-inline-log.md — check /dr-do completion".

## Hard-gated Action Boundary

**Verbatim** from `documentation/mandates/autonomous-agents.md:30-32` (do not quote from memory; do not paraphrase):

> Production deploys, secret rotation, irreversible DB operations (DROP / TRUNCATE without backup), public communications (Telegram channel posts, blog posts, social media), finance / legal actions, force-push to `main` / `master`, deletion of git history, and any action affecting > 1 human user.

**Carve-out (consumer mandate § Carve-out):** the consumer's `autonomous-agents.md` MAY define narrowly-scoped exceptions to this list. The reference Arcanada mandate carves out **autonomous public-package release of patch / minor versions** when every fail-closed pre-publish gate is green (`escalate=false`); `major` and any `0.x` breaking change still escalate, with a GitHub conditional `environment` as a second backstop. The machine-readable shape is `plugins/dr-orchestrate/rules/fb-rules.yaml` § `hard_gate_carve_outs`. Read the consumer mandate's carve-out section before treating a release action as hard-gated — do not quote the carve-out from memory.

Under `/dr-auto`, these actions **never auto-execute** (except where a consumer-mandate carve-out applies and all its preconditions are met):

1. The agent recognises the action as hard-gated (against the verbatim list or as a cross-project boundary crossing).
2. Escalate via Ladder L5: call `AskUserQuestion` and state explicitly "This action is hard-gated per autonomous-agents.md:32. Operator approval required before execution."
3. Log the operator response via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator --question "<question text>" --answer "<operator response>"`.

**Cross-project boundary (additional rule):** any action that touches repositories outside the task's project scope (the scope is defined by the Task Prefix Registry — `Arcanada/CLAUDE.md` or `documentation/architecture/task-prefix-registry.md`) is also hard-gated. Example: a task with prefix `SUP-` tries to edit `Projects/Verdicus/` → hard-gated.

**Workspace branch discipline (pre-file-edit check):** before editing any file in a workspace-root repository (one outside the task's own code repo — e.g. a shared mandate or doc tree), confirm `git branch --show-current` matches the active task. In a shared workspace with several parallel task branches checked out, a routine edit otherwise lands on whichever branch happens to be current and travels with the wrong merge. If the current branch does not match the task, create a task-named branch (or escalate) before writing — do not edit on a sibling task's branch.

**Not hard-gated:** infra-side actions on Arcanada-owned resources (SSH, `docker restart`, `git push` on a feature branch, Vault read, Cloudflare API read) — these are permitted per `feedback_autonomous_ops`.

## Failure modes

- **Env-var leak**: a parent shell kept `DATARIM_AUTO_MODE=1` set after `/clear`. **Mitigation:** mismatch detection (env var set, marker absent) treats the situation as non-auto and emits a warning. The 24h marker TTL prevents stale leaks from carrying further.
- **Stale marker**: a marker survived a crashed session. **Mitigation:** the 24h TTL; any marker for a non-current task is silently purged before activation.
- **Ladder false confidence**: L1-L4 returned an answer, but it is wrong (the grep matched a misleading line). **Mitigation:** the ambiguity rule — two or more candidates always escalate; a single candidate is treated as valid; the Q&A append-log lets the operator roll back later.
- **Coworker context leak (L4)**: bulk-read paths accidentally include credentials. **Mitigation:** reuse the existing coworker safety contract — paths under `~/arcanada/config/credentials/` are excluded; Ladder L4 calls `coworker ask` with an explicit path list, never a wildcard.
- **Cross-project unauthorised writes**: the agent edits a repo outside the task's project scope. **Mitigation:** the cross-project boundary is hard-gated; a runtime check fires before any file write.
- **L1 Inline Rule misclassification**: an L2 action is classified as L1 → silent contract drift. **Mitigation:** "when in doubt — classify up" is built into the decision tree; the auto-inline-log entry is mandatory so reviewers can audit.
- **Pre-archive workspace gate over-strict on foreign untracked files**: `scripts/pre-archive-check.sh` treats parallel-session untracked files (foreign social posts, a sibling-project site, framework test fixtures owned by other TASK-IDs) as `unattributed = default-deny` and blocks the archive. **Mitigation:** for own files mixed into a foreign-attributed diff — apply the HEAD-restore-and-reapply technique (restore the HEAD version, then apply only the current task's changes, then re-stage); for genuinely foreign untracked artefacts — use a manual override (skip the script gate) and document the file list in the archive's "Operator Handoff" section. The long-term fix is tracked as a Class B backlog item.

## How commands consume this skill

Each of the seven pipeline commands (`dr-init`, `dr-prd`, `dr-plan`, `dr-do`, `dr-qa`, `dr-compliance`, `dr-archive`) carries a `## /dr-auto Mode` section right after its `## Instructions` block:

```markdown
## /dr-auto Mode (when DATARIM_AUTO_MODE=1)

When auto-mode is active (env var + matching marker), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder before any `AskUserQuestion` or equivalent operator prompt.
2. Applies stage-specific suppression hooks:
   - <stage-specific list: e.g. for /dr-init: skip Discovery Interview round 2 if every question resolved through L1-L4>
   - <for /dr-do: apply the L1 Inline Rule against gaps discovered during execution>
   - <for /dr-archive: consume auto-inline-log.md before reflection>
3. For any discovered gap: apply the L1 Inline Rule per `skills/autonomous-mode/SKILL.md`; log to `datarim/tasks/{TASK-ID}-auto-inline-log.md` when resolved inline.
4. For hard-gated actions: escalate to the operator via Ladder L5, log through `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator`.
```

## Related

- `commands/dr-auto.md` (the caller — activates this skill, sets the env var, and writes the marker)
- `documentation/mandates/autonomous-agents.md` (the FB-1..8 mandate — source of truth for every rule activated here)
- `skills/cta-format/SKILL.md` § Snapshot Emission (terminal-step contract at the end of each stage)
- `skills/init-task-persistence/SKILL.md` § Q&A round-trip (the L5 logging mechanism via `append-init-task-qa.sh`)
- Memory: `feedback_l1_proposals_close_in_cycle` (the L1-rule precedent, originally scoped to `/dr-archive` only)
- Memory: `feedback_autonomous_ops` (the infra-side autonomy scope — SSH / Cloudflare / Vault / docker / git on Arcanada resources)
