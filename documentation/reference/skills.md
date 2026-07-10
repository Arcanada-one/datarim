# Skills Reference

Datarim includes 64 reusable skill modules. Skills provide rules, patterns, and guidelines loaded on demand by agents and commands.

Skills are split into two categories:
- **Reference skills** — rules and patterns the caller applies inline. Inherit caller's model (no `model` field).
- **Task skills** — perform an action when invoked. Have explicit `model` field per [Model Assignment Convention](../skills/datarim-system/SKILL.md).

## Skill Catalog

| Skill | Type | Model | Purpose | Loaded By |
|-------|------|-------|---------|-----------|
| datarim-system | Reference | inherit | Core workflow rules, path resolution, file locations | All commands (mandatory) |
| cta-format | Reference | inherit | Canonical CTA "Next Step" block format (v1.16.0, TUNE-0032) | planner, architect, developer, reviewer, compliance |
| ai-quality | Reference | inherit | 5 pillars: decomposition, TDD, architecture-first, focus, context | developer, planner |
| security | Reference | inherit | Auth, input validation, data protection | reviewer, security agent |
| testing | Reference | inherit | Testing pyramid, frameworks, mocking rules | developer, reviewer |
| performance | Reference | inherit | Lazy loading, caching, batching, DB optimization | architect, sre |
| tech-stack | Reference | inherit | Stack selection by project type | planner, architect |
| consilium | Task | opus | Multi-agent panel discussions | /dr-design (L3-4) |
| evolution | Task | opus | Framework self-update rules | /dr-archive (Step 0.5 via reflecting skill), /dr-optimize |
| reflecting | Task | inherit | Review-phase workflow: lessons learned, evolution proposals with Class A/B gate, health-metrics check, follow-up-task detection | /dr-archive (Step 0.5, internal only) |
| incident-investigation | Task | opus | Root cause analysis for incidents | sre, on demand |
| compliance | Task | sonnet | 7-step post-QA hardening workflow | compliance agent |
| discovery | Task | sonnet | Requirements discovery interview | /dr-prd |
| dream | Task | sonnet | Knowledge base maintenance rules | librarian |
| factcheck | Task | sonnet | Fact verification for publications | editor, on demand |
| humanize | Task | sonnet | AI text pattern removal | editor, on demand |
| go-to-market | Task | sonnet | SEO, analytics, ad campaigns, launch checklists | on demand |
| visual-maps | Task | sonnet | Mermaid workflow diagrams | on demand |
| writing | Task | sonnet | Content creation and editorial workflow | writer, editor |
| utilities | Task | haiku | Native shell recipes for common operations (15 fragment files) | Any agent (on demand) |
| datarim-doctor | Task | sonnet | /dr-doctor schema and migration semantics (thin one-liner contract) | /dr-doctor, /dr-init self-heal, /dr-archive line-format gate |
| file-sync-config | Reference | inherit | Pre-flight checklist + ignore patterns for file-sync (Syncthing/rclone) | on demand for sync setup |
| frontend-ui | Task | sonnet | CSS specificity, dark/light themes, visual testing, mobile responsiveness | when editing HTML/CSS |
| infra-automation | Task | sonnet | SSH batch execution, health checks, network debugging, pre-migration inventory | server ops tasks |
| project-init | Task | sonnet | Project scaffolding (CLAUDE.md, documentation/, datarim/ structure) | /dr-init when project intent detected |
| publishing | Task | haiku | Multi-platform publishing rules, formatting, platform limits | writer, on demand |
| release-verify | Reference | inherit | Consumer-side release verification (sha256 → cosign verify-blob → gh attestation) | on install/update from GitHub Release |
| research-workflow | Task | sonnet | Structured external research methodology, checklist, tool selection | researcher agent in /dr-prd, /dr-do |
| security-baseline | Reference | inherit | Canonical S1–S9 security rule reference cited from CLAUDE.md § Security Mandate | plan/qa/compliance/do touching shipped artefacts |
| diataxis-docs | Reference | inherit | Documentation Taxonomy Mandate — 4 closed Diátaxis categories (tutorials / how-to / reference / explanation), mapping table, exemption list, anti-patterns | /dr-init project scaffolding, /dr-optimize audit, /dr-archive surface verification |
| init-task-persistence | Reference | inherit | Verbatim operator brief artefact contract — frontmatter + append-log + Q&A round-trip auto-append (v2.9.0); mandatory read by every pipeline command | All pipeline commands (mandatory READ at first step; six write Q&A blocks via `dev-tools/append-init-task-qa.sh`) |
| expectations-checklist | Reference | inherit | Operator wishlist artefact (Option B flat markdown) — wish_id slug + История статусов + Текущий статус + override semantics. Schema v2 (2.17.1) adds mandatory `evidence_type: empirical \| static \| measurement` per wish; mandate scope extended to all L1-L4 (no soft window). | /dr-init Step 4.7 (create skeleton, L1-L4); /dr-prd, /dr-plan (append-merge); /dr-qa, /dr-compliance (verify + per-wish detailed block in qa-report) |
| playwright-qa | Task | sonnet | Browser-based frontend QA — CLI / MCP / env-browser resolution chain + headed / headed-strict + per-task flock + run-`<ISO-ts>`/ artefacts | /dr-qa Layer 4f on frontend touch |
| human-summary | Reference | inherit | Plain-language operator recap — four sub-sections + banlist + whitelist + per-paragraph escape hatch + 150–400 word budget | /dr-qa, /dr-compliance, /dr-archive (Step 8) |
| stage-snapshot-writer | Reference | inherit | Producer contract for per-task stage snapshots — final operator-visible `/dr-*` response persisted to `datarim/snapshots/{TASK-ID}.snapshot.md` with overwrite semantics, mkdir-based atomic lock, 8 KB hard cap (v2.13.0, TUNE-0254) | invoked from `cta-format.md` § Snapshot Emission by every `/dr-*` |
| dr-next-snapshot-replay | Reference | inherit | Consumer contract — `/dr-next` and `/dr-orchestrate` read snapshot first, emit replay-prompt with CTA + bilingual autonomy reminder + `done before:` body; CTA-selection heuristic with ≥3 worked examples (v2.13.0, TUNE-0254) | `/dr-next` Step 2.5, `/dr-orchestrate` Snapshot-First Resume |
| v-ac-axis-split | Reference | inherit | Pattern guidance: split V-AC groups mixing a deterministic axis (rule match / shape check / type assertion) and a statistical axis (live-rate threshold / SLA percentile / soak distribution) into two distinct V-AC groups upfront. | `/dr-prd` V-AC drafting, `/dr-plan` V-AC review |
| prod-readiness-probe | Reference | inherit | Deploy-class prod-readiness gate — read-only test↔prod runner symmetry probe (sudoers, PATH, ports, units, runtime versions); blocks merge-proposal at `/dr-qa` Gate 4g and archive at `/dr-archive` Step 0.4 until prod is verified; hybrid deterministic (`deploy-readiness.yml`) / agent-checklist | `/dr-qa` Gate 4g, `/dr-archive` Step 0.4 |
| session-handoff-writer | Reference | inherit | Producer contract for `/dr-save` — writes `datarim/sessions/SESSION-{YYYYMMDD-HHMMSS}.session.md` with 5-layer body, 32 KB cap (L1/L5 non-truncatable), append-only semantics, claim-provenance enforcement (exit 1 on untagged claims), T-8 secret redaction, mkdir-based atomic lock, chmod 600. | `/dr-save` |
| session-handoff-replay | Reference | inherit | Consumer contract for `/dr-continue` — reads session artefact in a clean window, re-verifies every claim via live probes (STALE SNAPSHOT / CLAIM-UNVERIFIED / FILE-MISSING banners), downgrades provenance tags, routes to `/dr-next` or `/dr-auto`. Squash-collision detection via `git merge-base --is-ancestor`. Shares bilingual replay renderer with `/dr-next` via `skills/dr-next-snapshot-replay/SKILL.md § Shared Replay Renderer`. | `/dr-continue` |
| image-prompting | Reference | inherit | Playbook for authoring image-generation prompts (covers, thumbnails, post visuals, illustrations, infographics, logos) — intake → spec → prompt → verify loop, composition / camera / light / palette language, text-in-image constraints, negative constraints + invariants, native aspect/size handling for gpt-image-style tools, iterative refinement, reusable-templates fragment (`prompt-templates.md`), verification checklist | writer, editor, on demand for any visual asset |
| cron-agent-patterns | Reference | inherit | Layered timeout defense for cron-orchestrated agents making external calls (LLM CLI / HTTP / subprocess) — strictly-nested tiers (per-call < cycle deadline < SIGALRM net < shell `timeout --kill-after`), anti-patterns (per-call==budget, `max(N, deadline-now)` floor, `except Exception: pass` swallowing SIGALRM), symmetric deadline guards + explicit next-tier headroom (`*_RESERVE_SEC`) | on demand for cron / timer agents with external API calls |
| nginx-version-compat | Reference | inherit | Probe running nginx version (`nginx -v` / `nginx -V`) before editing config, then map directive syntax to that version (HTTP/2 `listen ... http2` legacy vs `http2 on;` from 1.25.1; HTTP/3 `quic`/`http3` from 1.25.0+) + common breaking-change traps | `/dr-plan` for any nginx-touching task |
| plan-path-validator | Reference | inherit | Exists-check for file/script/path references in a plan output — flags MISSING (phantom) and DEPRECATED (stale) paths before /dr-do, via git-topology-aware `test -e` / `git cat-file` probes | /dr-plan Validation Checklist (companion to § 6.5 Symbol Existence Check), /dr-qa plan review |
| v-ac-feasibility | Reference | inherit | Pre-implementation gate proving every runtime-command V-AC (docker exec / curl / kubectl / systemctl / live DB query) can actually PASS under a correct implementation before /dr-do — dry-run against real/skeleton runtime or named observation path; infeasible-pattern table | /dr-plan Step 6.5 V-AC review |

**Distribution:** 22 reference (inherit), 3 opus, 13 sonnet, 4 haiku.

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
model: sonnet  # or opus / haiku per Model Assignment Convention
---

# {Skill Title}

(Step-by-step instructions, checklists, workflows — performs an action when invoked)
```

See [Model Assignment Convention](../skills/datarim-system/SKILL.md) in `datarim-system.md` for choosing the right model.
