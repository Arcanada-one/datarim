---
name: consilium
description: Assemble a panel of Datarim agents for multi-perspective analysis of decisions. Use for /dr-design stage (L3-4) or critical decisions in /dr-plan.
model: inherit
current_aal: 1
target_aal: 3
---

# Consilium — Multi-Agent Panel Discussions

## What is Consilium

Consilium is a structured council of Datarim agents debating a decision. Instead of a single perspective, the agent simulates multiple specialized viewpoints — architect, security analyst, SRE, strategist — to surface conflicts, blind spots, and tradeoffs before committing to a path.

Use Consilium for:
- Architecture decisions with lasting impact
- Trade-off analysis where no obvious "right answer" exists
- Production readiness assessments
- New feature evaluation at L3-4 complexity

**Do NOT use Consilium for:** L1-2 tasks, simple bug fixes, or questions with clear answers. Over-consilium wastes time.

---

## Pipeline

```
SCOPE → ASSEMBLE → ANALYZE → DEBATE → CONVERGE → DELIVER
```

---

## Step 1: SCOPE

Define the question clearly before assembling the panel.

**Required:**
- **Question:** One sentence. What decision needs to be made?
- **Context:** What constraints, history, and goals are relevant?
- **Blast radius:** How far does this decision reach?

### Blast Radius Classification

| Level | Name | Description | Example |
|-------|------|-------------|---------|
| 1 | Contained | Single module/file, easily reversible | Rename internal function |
| 2 | Host-level | Multiple files in one service | Change data model |
| 3 | Cross-system | Multiple services or external APIs | New auth provider |
| 4 | Business-critical | Revenue, users, compliance, or data integrity | Payment flow redesign |

**Rule:** Blast radius 1-2 rarely needs Consilium. Reserve it for 3-4.

---

## Step 2: ASSEMBLE

Select agents based on the question domain. Load each agent's file from `$HOME/.claude/agents/{name}.md`.

### Preset Panels

| Decision Type | Agents | Why |
|--------------|--------|-----|
| Architecture decision | architect, strategist, security, sre, devops | Structural choices need ops + security perspective |
| Code design | developer, reviewer, code-simplifier | Implementation quality needs review lens |
| Production readiness | sre, devops, security | Reliability + security gate before release |
| New feature | strategist, architect, developer, writer | Business alignment + technical feasibility + docs |
| Performance | sre, architect, developer | Load patterns + structural limits + implementation |

### Custom Panel

For questions that don't fit a preset, pick 3-7 agents from the full roster:

`planner, architect, developer, reviewer, compliance, code-simplifier, strategist, devops, writer, security, sre`

**Rules:**
- Minimum 3 agents for meaningful discussion
- Maximum 7 agents — more creates noise, not signal
- Always include at least one agent who will challenge the majority

---

## Step 3: ANALYZE

Each agent evaluates the question through their specialized lens.

**Format per agent:**

```markdown
### {Agent Name} — {Role}

**Position:** [Support / Oppose / Conditional support]

**Analysis:**
- [Key observation from this agent's perspective]
- [Risk or opportunity only this agent would see]
- [Recommendation with rationale]

**Conditions:** [What must be true for their recommendation to work]
```

**Rules:**
- Each agent speaks independently — do not blend perspectives
- Focus on what only THIS agent would notice
- Be specific — "security risk" is useless, "unauthenticated endpoint at /api/export exposes PII" is useful

---

## Step 4: DEBATE

Surface conflicts between agents. Not every analysis will agree — that is the point.

### Conflict Table

| Agent A | Agent B | Conflict | Resolution Path |
|---------|---------|----------|-----------------|
| architect | sre | Architect wants microservices; SRE wants monolith for operational simplicity | Evaluate team size and ops maturity |
| developer | security | Developer wants to store tokens in localStorage for simplicity; Security requires httpOnly cookies | Security wins — use httpOnly cookies |

**Rules:**
- Only real conflicts. If agents agree, skip DEBATE.
- Each conflict must have a resolution path (even if "needs more data")
- Maximum 2 rounds of debate. If unresolved after 2 rounds, escalate to CONVERGE.

---

## Step 5: CONVERGE

Resolve remaining conflicts using the Priority Ladder. Higher priority wins.

### Priority Ladder

```
1. Safety        — Will anyone get hurt?
2. Correctness   — Does it produce the right result?
3. Security      — Is it protected against threats?
4. Reliability   — Will it stay up under load?
5. Simplicity    — Can the team maintain it?
6. Cost          — Is it affordable?
7. Elegance      — Is it beautiful?
```

When two agents conflict, the one whose concern ranks higher on this ladder wins. If concerns are at the same level, prefer the option that is simpler to implement and easier to reverse.

---

## Step 6: DELIVER

Produce the final output.

### Recommendation

```markdown
## Consilium Recommendation

**Question:** {original question}
**Panel:** {list of agents}
**Verdict:** {chosen path}

### Rationale
{Why this path was chosen, referencing the Priority Ladder if conflicts were resolved}

### Dissenting Opinions
{Any agents who disagreed and why — these are valuable signals, not noise}

### Failure Mode Table

| What Can Fail | Probability | Impact | Detection | Mitigation |
|--------------|-------------|--------|-----------|------------|
| {specific failure} | Low/Med/High | Low/Med/High | {how you would notice} | {what you would do} |

### Conditions & Assumptions
{What must remain true for this recommendation to hold}
```

---

## Guard Rules

1. **Don't over-consilium.** L1-2 tasks get simple answers. Only invoke Consilium for L3-4 or when blast radius is 3-4.
2. **Max 7 agents per panel.** More agents create noise without proportional insight.
3. **Each agent speaks once per round, max 2 rounds.** Prevents circular debate.
4. **If unanimous after ANALYZE — skip DEBATE.** Agreement is a valid outcome. Proceed directly to DELIVER.
5. **Time-box:** If you cannot converge in 2 rounds, deliver with unresolved conflicts noted as open questions for the human to decide.

---

## Real Multi-Vendor Mode

This section describes how to run a Consilium panel where each position is drafted
by a **distinct vendor CLI** running as a live interactive agent — not simulated
by a single model adopting different personas. Use it when you need true
stylistic independence and provenance-traceable authorship across drafts.

### When to use

- Content creation tasks where voice diversity matters (articles, social posts, long-form)
- Quality-lift validation: confirm that multi-vendor output is measurably better than
  single-model output before committing to the orchestration overhead
- Any context where a single model's priors could dominate all "perspectives"

### How it differs from single-agent Consilium

| Dimension | Single-agent Consilium | Real Multi-Vendor Mode |
|-----------|------------------------|------------------------|
| Who generates each position | One model role-playing multiple agents | One distinct vendor CLI per position |
| Voice independence | Structural (persona prompts) | True (different model weights) |
| Provenance | Implied by role label | Recorded in run-log per vendor slot |
| Overhead | Low (one model call) | Higher (N parallel CLI sessions) |
| Degradation | No — single point of failure | Yes — 2-of-N graceful degradation |

### 3-tier architecture

Real Multi-Vendor Mode is implemented across three tiers:

- **Tier-1 (this skill):** Protocol contract only. No vendor names, no CLI
  literals, no hostnames. The skill describes the _what_ and _why_.
- **Tier-2 (dr-orchestrate plugin):** Fan-out + judge scripts. Vendor CLI
  invocations, run-log format, scoring matrix, degradation logic. Install via
  `/dr-plugin enable dr-orchestrate`. Scripts: `content_consilium_fanout.sh`
  and `content_consilium_judge.sh`.
- **Tier-3 (workspace config):** Operator-local vendor map. Which CLI binary
  maps to which slot. Lives in `datarim/pub-consilium/` (gitignored).

### Fan-out protocol

1. The orchestrator reads the brief and vendor config.
2. It spawns one tmux session per vendor using the `dr-orchestrate` plugin
   helpers (`session_spawn_interactive` / `pane_send` / `pane_capture_tail`).
3. Each vendor receives the identical brief plus its role label ("Vendor A",
   "Vendor B", "Vendor C") — no cross-vendor information leaks.
4. The orchestrator polls each session for completion using `pane_idle_check`.
5. Completed drafts are written to `datarim/pub-consilium/{RUN-ID}/draft-*.md`.
6. A run-log entry is appended for each vendor: `{vendor_slot, status, elapsed_s}`.

### Degradation rules

- **3-of-3 available:** full fan-out, judge receives all three drafts.
- **2-of-3 available (one vendor timed out or errored):** fan-out proceeds
  with the two healthy vendors; the run-log records the degraded vendor and
  reason; the judge output includes a `degradation_note` field.
- **Fewer than 2 available:** the fan-out script exits non-zero; the operator
  is notified; no draft is selected.
- **Hang detection:** if a vendor pane produces no new output for the
  configured `HANG_IDLE_SECS` (default 120), it is classified as hung,
  its session is closed, and it counts as unavailable.

### Judge protocol

After fan-out, the judge script reads all available drafts and:

1. Scores each draft on the per-stage criteria defined in the vendor config.
2. Produces a `judge-decision.md` with the scoring matrix, rationale, and
   a pointer to the winning draft.
3. Copies the winning draft to `final.md` in the run directory.
4. Records traceability: which vendor slot produced the selected draft.

The judge runs natively (same session) and MUST NOT delegate draft generation to
an external writing assistant — the point is to evaluate vendor-authored text,
not to generate a new synthesis.

### Invoking via content commands

When the `--consilium` flag (or `DATARIM_CONSILIUM=1`) is passed to
`/dr-write`, `/dr-edit`, or `/dr-publish`, those commands activate the
multi-vendor branch described in their own `## Multi-Vendor Consilium Mode`
section and delegate to the `dr-orchestrate` plugin. The single-agent
default path is unchanged when the flag is absent.
