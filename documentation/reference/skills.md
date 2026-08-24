# Skills Reference

Datarim includes 74 reusable skill modules. Skills provide rules, patterns, and guidelines loaded on demand by agents and commands. Each skill is a directory under `skills/` containing a `SKILL.md` plus any supporting fragment files.

Skills are split into two categories:
- **Reference skills** — rules and patterns the caller applies inline. No `model` field in frontmatter, so they inherit the caller's model. 54 of the 74.
- **Task skills** — perform an action when invoked. Carry an explicit `model` field per the [Model Assignment Convention](../../skills/datarim-system/SKILL.md). 20 of the 74.

Every shipped skill resolves to `inherit` — the operator's session model wins. Pinning a concrete model generation in a skill breaks under runtimes that do not offer it; express capability intent with `metadata.model_tier:` (resolved through `config/model-tiers.yaml`) instead.

## Skill Catalog

Alphabetical. "Loaded by" names the commands, agents, or trigger conditions that pull the skill in.

| Skill | Type | Purpose | Loaded By |
|-------|------|---------|-----------|
| adversarial-review | Reference | Forces an adversarial mindset on an artifact (plan, PRD, code, design) — break it, do not bless it | /dr-plan Transition Checkpoint, /dr-qa |
| ai-quality | Reference | 5 pillars: decomposition, TDD, architecture-first, focus, context | developer, planner |
| autonomous-mode | Task | Question Suppression Ladder + L1 Inline Resolution Rule + hard-gated action boundary; activated by `DATARIM_AUTO_MODE=1` plus a per-task marker | /dr-auto, and every pipeline command when the marker is present |
| brainstorming | Reference | Explore user intent and design before implementation; mandatory before creative work on features, components, or behaviour changes | on demand, before creative work |
| compliance | Task | 7-step post-QA hardening workflow | compliance agent |
| consilium | Task | Multi-agent panel discussions | /dr-design (L3-4) |
| context-window-self-clearing | Reference | Default-off orchestrator contract for checkpoint-before-reset context compaction/clearing and snapshot-first continuity across Claude Code and Codex | /dr-orchestrate plugin runtime |
| coworker-context | Reference | Conventions an external LLM (via coworker delegation) must follow when generating or editing Datarim artifacts — stage header, frontmatter, and so on | coworker `datarim` write profile, /dr-write, /dr-archive |
| cron-agent-patterns | Reference | Layered timeout defense for cron-orchestrated agents making external calls (LLM CLI / HTTP / subprocess) — strictly-nested tiers, anti-patterns, symmetric deadline guards with explicit next-tier headroom | on demand for cron / timer agents with external API calls |
| cta-format | Reference | Canonical CTA "Next Step" block format | planner, architect, developer, reviewer, compliance |
| customer-delivery | Reference | Trace verbatim customer requirements through pre-work knowledge binding, implementation, production evidence, and disposition without treating enabling output as delivery | customer-facing work |
| datarim-doctor | Reference | /dr-doctor schema and migration semantics (thin one-liner contract) | /dr-doctor, /dr-init self-heal, /dr-archive line-format gate |
| datarim-system | Reference | Core workflow rules, path resolution, file locations | All commands (mandatory) |
| edge-case-hunter | Reference | Enumerates boundary, degenerate, and failure inputs an artifact does not visibly handle | /dr-plan, /dr-qa |
| diataxis-docs | Reference | Documentation Taxonomy Mandate — 4 closed Diátaxis categories, mapping table, reserved siblings, exemption list, anti-patterns | /dr-init project scaffolding, /dr-optimize audit, /dr-archive surface verification |
| discovery | Task | Requirements discovery interview | /dr-prd |
| dispatching-parallel-agents | Reference | Recognise 2+ independent tasks that can run without shared state or sequential dependencies, and dispatch them in parallel | skill-creator, on demand |
| dr-init-id-collision-window | Reference | Detect and resolve task-ID collisions in the TOCTOU window between /dr-init reservation and /dr-archive completion — archive-wide grep, sed-batch rename, `git mv` coordination, chmod restore for locked verify logs | /dr-init (probe step), /dr-archive (collision-detection branch) |
| dr-next-snapshot-replay | Reference | Consumer contract — /dr-next and /dr-orchestrate read the snapshot first, then emit a replay prompt with CTA, bilingual autonomy reminder, and `done before:` body | /dr-next Step 2.5, /dr-orchestrate Snapshot-First Resume |
| dream | Task | Knowledge base maintenance rules | librarian |
| evolution | Task | Framework self-update rules | /dr-archive (Step 0.5 via reflecting skill), /dr-optimize |
| executing-plans | Reference | Execute a written implementation plan in a separate session with review checkpoints | on demand, when a plan artefact exists |
| expectations-checklist | Reference | Operator wishlist artefact (flat markdown) — `wish_id` slug, status history, current status, and override semantics. Schema v4 requires explicit customer derivation on every wish and a delivery binding for customer-derived wishes; v1-v3 remain frozen legacy inputs | /dr-init Step 4.7 (skeleton, L1-L4); /dr-prd, /dr-plan (append-merge); /dr-qa, /dr-compliance (verify + per-wish block in the QA report) |
| factcheck | Task | Fact verification for publications | editor, on demand |
| file-sync-config | Reference | Pre-flight checklist + ignore patterns for file-sync (Syncthing/rclone) | on demand for sync setup |
| finishing-a-development-branch | Reference | Decide how to integrate completed work — merge, PR, or cleanup — via structured options, once implementation is done and tests pass | on demand at end of branch work |
| fleet | Task | Router for the five-tier fleet starter skill (l1-basic..l5-autonomous) — selects the AAL/complexity level and its context budget for a spawned agent | /dr-init, /dr-prd, /dr-orchestrate |
| frontend-design | Reference | Research-backed pre-code design packets for rendered customer-facing frontend work, with deterministic routing and Knowledge Contract handoff | designer; before frontend implementation |
| frontend-ui | Task | CSS specificity, dark/light themes, visual testing, mobile responsiveness | when editing HTML/CSS |
| health-controller-stub-detector | Reference | Surface hard-coded stub literals (`pending-integration`, `not-implemented`, `stub`) in health/status controllers at /dr-do, before /dr-qa wish gating | /dr-do, when a health or status controller is touched |
| human-summary | Reference | Plain-language operator recap — four sub-sections + banlist + whitelist + per-paragraph escape hatch + 150–400 word budget | /dr-qa, /dr-compliance, /dr-archive (Step 8) |
| humanize | Task | AI text pattern removal | editor, on demand |
| image-prompting | Task | Playbook for authoring image-generation prompts (covers, thumbnails, post visuals, illustrations, infographics, logos) — intake → spec → prompt → verify loop, composition / camera / light / palette language, text-in-image constraints, negative constraints, reusable templates fragment | writer, editor, on demand for any visual asset |
| immutability | Task | Immutability contract for all pipeline stages — artefact freeze, V-AC parity, non-code parity, anti-tautological rule, return-to-source transition | architect; /dr-prd, /dr-plan, /dr-design, /dr-do, /dr-qa, /dr-compliance |
| infra-automation | Task | SSH batch execution, health checks, network debugging, pre-migration inventory | server ops tasks |
| init-task-persistence | Reference | Verbatim operator brief artefact contract — frontmatter + append-log + Q&A round-trip auto-append; mandatory read by every pipeline command | All pipeline commands (mandatory READ at first step; six write Q&A blocks via `dev-tools/append-init-task-qa.sh`) |
| network-exposure-baseline | Reference | Allowlist/blocklist for network bind targets (compose ports, redis bind, postgres `listen_addresses`, systemd `ListenStream`); load before any port change | /dr-prd, /dr-plan, /dr-do on any port or bind change |
| nginx-version-compat | Reference | Probe the running nginx version (`nginx -v` / `nginx -V`) before editing config, then map directive syntax to that version, plus common breaking-change traps | /dr-plan for any nginx-touching task |
| performance | Reference | Lazy loading, caching, batching, DB optimization | architect, sre |
| plan-path-validator | Reference | Exists-check for file/script/path references in a plan output — flags MISSING (phantom) and DEPRECATED (stale) paths before /dr-do | /dr-plan Validation Checklist, /dr-qa plan review |
| playwright-qa | Reference | Browser-based frontend QA — CLI / MCP / env-browser resolution chain + headed / headed-strict + per-task flock + run-`<ISO-ts>`/ artefacts | /dr-qa Layer 4f on frontend touch |
| post-deploy-env-diff | Reference | Pre-archive gate diffing the on-host env file against the repo template when a deploy changed defaults — catches a production host left on a stale `.env` | /dr-archive, after any deploy that changed env defaults |
| prod-readiness-probe | Reference | Deploy-class prod-readiness gate — read-only test↔prod runner symmetry probe (sudoers, PATH, ports, units, runtime versions); blocks the merge proposal at /dr-qa and archive at /dr-archive until prod is verified | /dr-qa Gate 4g, /dr-archive Step 0.4 |
| project-init | Reference | Project scaffolding (CLAUDE.md, documentation/, datarim/ structure) | /dr-init when project intent detected |
| publishing | Task | Multi-platform publishing rules, formatting, platform limits | writer, on demand |
| receiving-code-review | Reference | Handle review feedback before implementing suggestions — technical verification instead of performative agreement or blind implementation | on demand, when review feedback arrives |
| reflecting | Reference | Review-phase workflow: lessons learned, evolution proposals with Class A/B gate, health-metrics check, follow-up-task detection | /dr-archive (Step 0.5, internal only) |
| release-verify | Reference | Consumer-side release verification (sha256 → cosign verify-blob → gh attestation) | on install/update from a GitHub Release |
| requesting-code-review | Reference | Verify that work meets requirements before merge — used when completing tasks or implementing major features | on demand, before merge |
| research-workflow | Task | Structured external research methodology, checklist, tool selection | researcher agent in /dr-prd, /dr-do |
| rotation-runbook | Reference | Credential rotation playbook — consumer inventory, auth-scoped verification, full payload replay, canonical secret paths, rotation log | on demand, for any planned rotation or leak response |
| seam-vs-integration-boundary | Reference | Plan-time scope-boundary pattern: split a one-liner that bundles a seam/contract concern with an integration/call-site concern, or scope the ACs so the integration is explicitly deferred. Advisory detector `dev-tools/check-seam-integration-boundary.sh` | /dr-plan Phase 4 Component Breakdown |
| security | Reference | Auth, input validation, data protection | reviewer, security agent |
| security-baseline | Reference | Canonical S1–S11 security rule reference cited from CLAUDE.md § Security Mandate | plan/qa/compliance/do touching shipped artefacts |
| self-verification | Reference | Orchestrator for runtime-aware self-verification — tri-layer: deterministic shell floor, peer review, runtime dispatch | /dr-verify; also /dr-prd, /dr-plan, /dr-do, peer-reviewer agent |
| session-handoff-replay | Reference | Consumer contract for /dr-continue — reads the session artefact in a clean window, re-verifies every claim via live probes (stale-snapshot / unverified-claim / missing-file banners), downgrades provenance tags, routes to /dr-next or /dr-auto. Squash-collision detection via `git merge-base --is-ancestor` | /dr-continue |
| session-handoff-writer | Reference | Producer contract for /dr-save — writes `datarim/sessions/SESSION-{YYYYMMDD-HHMMSS}.session.md` with 5-layer body, 32 KB cap (L1/L5 non-truncatable), append-only semantics, claim-provenance enforcement, secret redaction, mkdir-based atomic lock, chmod 600 | /dr-save |
| stage-snapshot-writer | Reference | Producer contract for per-task stage snapshots — the final operator-visible `/dr-*` response persisted to `datarim/snapshots/{TASK-ID}.snapshot.md` with overwrite semantics, mkdir-based atomic lock, 8 KB hard cap | invoked from `cta-format.md` § Snapshot Emission by every `/dr-*` |
| structured-outputs-integration-gate | Reference | Demand schema-unit and wrapper-path tests when API-side structured-output validation is added on top of an existing post-processing pipeline | on demand, when structured-output validation is introduced |
| subagent-driven-development | Reference | Execute implementation plans with independent tasks inside the current session, via subagents | on demand, during /dr-do |
| structure-review | Reference | Reviews an artifact's organisation, completeness, and internal consistency — does it hold together as a document | /dr-plan, /dr-qa |
| systematic-debugging | Reference | Structured approach to any bug, test failure, or unexpected behaviour — applied before proposing fixes | on demand, on any failure |
| tech-stack | Reference | Stack selection by project type | planner, architect |
| test-env-verification | Reference | Mandatory gate: verify the change on the test environment (backend + frontend) autonomously before prod prep or archive | blocks /dr-qa, /dr-compliance, /dr-archive |
| testing | Reference | Testing pyramid, frameworks, mocking rules | developer, reviewer |
| using-git-worktrees | Reference | Ensure an isolated workspace before feature work or plan execution, via native tools or a git worktree fallback | on demand, before isolated feature work |
| utilities | Task | Native shell recipes for common operations (fragment files per category) | Any agent (on demand) |
| v-ac-axis-split | Reference | Split V-AC groups that mix a deterministic axis (rule match / shape check / type assertion) with a statistical axis (live-rate threshold / SLA percentile / soak distribution) into two distinct groups upfront | /dr-prd V-AC drafting, /dr-plan V-AC review |
| v-ac-feasibility | Reference | Pre-implementation gate proving every runtime-command V-AC (docker exec / curl / kubectl / systemctl / live DB query) can actually PASS under a correct implementation before /dr-do | /dr-plan Step 6.5 V-AC review |
| verification-before-completion | Reference | Run verification commands and confirm their output before claiming work complete, fixed, or passing — and before committing or opening a PR | on demand, before any completion claim |
| visual-maps | Task | Mermaid workflow diagrams | on demand |
| wizard | Task | Interactive task-spec wizard — a thin orchestrator over discovery and consilium that turns a rough brief into a structured spec plus a graph artefact | /dr-wizard, /dr-prd |
| writing | Task | Content creation and editorial workflow | writer, editor |
| writing-plans | Reference | Turn a spec or set of requirements for a multi-step task into a written plan, before touching code | on demand, before implementation |

**Distribution:** 54 reference skills (no `model` field — inherit the caller), 20 task skills (explicit `model: inherit`).

## Loading Hierarchy

1. **Always loaded:** `datarim-system.md` (by every command)
2. **Per-stage:** Skills specified in agent's Context Loading section
3. **On demand:** Specialized skills loaded when the task requires them

## Skill File Format

**Reference skill** (no `model` field — inherits from caller):

```markdown
---
name: {skill-name}
description: {one-line description}
---

# {Skill Title}

(Rules, patterns, guidelines, templates — applied inline by caller)
```

**Task skill** (explicit `model` — required):

```markdown
---
name: {skill-name}
description: {one-line description}
model: inherit          # per Model Assignment Convention
metadata:
  model_tier: balanced  # optional capability intent: reasoning | balanced | fast | cheap
---

# {Skill Title}

(Step-by-step instructions, checklists, workflows — performs an action when invoked)
```

See [Model Assignment Convention](../../skills/datarim-system/SKILL.md) in `datarim-system.md` for choosing the right tier.
