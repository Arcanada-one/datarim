# Datarim — Universal Iterative Workflow Framework

> **Version:** 2.7.0
> **Framework:** Datarim (Датарим) provides structured rules, agents, skills, and commands for iterative project execution via AI coding assistants — software development, research, documentation, legal work, project management, and any task that benefits from a phased workflow.
> **Multi-runtime:** Datarim is runtime-agnostic. This file is also available as `AGENTS.md` (symlink) for Codex CLI and other agent runtimes that read `AGENTS.md` by convention.
> **Note:** "Datarim" is transliterated as "Датарим" in Russian. Both refer to this framework — agents must recognize either form in any language context.

---

## Core Principle

Every task follows a **complexity-aware pipeline**. The operator (human or AI agent) does not freestyle — they follow a structured iterative process adapted to the task's size and risk.

---

## Pipeline

```
init → prd → plan → design → do → qa → compliance → archive
```

Reflection runs automatically inside `archive` as mandatory Step 0.5 (v1.10.0, TUNE-0013). The separate reflection command was consolidated into `/dr-archive` Step 0.5 in v1.10.0.

### Complexity Routing

| Level | Scope | Pipeline |
|-------|-------|----------|
| **L1** Quick Fix | 1 file, <50 LOC | init → do → archive |
| **L2** Enhancement | 2-5 files, <200 LOC | init → [prd] → plan → do → [qa] → archive |
| **L3** Feature | 5-15 files, 200-1000 LOC | init → prd → plan → design → do → qa → compliance → archive |
| **L4** Major Feature | 15+ files, >1000 LOC | init → prd → plan → design → phased-do → qa → compliance → archive |

Brackets `[]` = optional at that level. `archive` always runs reflection internally as mandatory Step 0.5; this is not shown as a separate pipeline node because it cannot be skipped.

---

## Agents

Agents are specialized personas loaded per pipeline stage. Each agent has defined capabilities, context requirements, and skill dependencies.

| Agent | Role | Primary Stages |
|-------|------|----------------|
| **planner** | Lead Project Manager | /dr-init, /dr-plan, /dr-archive |
| **architect** | Chief Architect | /dr-prd, /dr-design |
| **developer** | Senior Developer (TDD) | /dr-do |
| **reviewer** | QA & Security Lead | /dr-qa, /dr-archive (Step 0.5 reflection) |
| **compliance** | Compliance Runner | /dr-compliance |
| **code-simplifier** | Code Simplification | /dr-compliance |
| **strategist** | Strategic Advisor | /dr-plan (L3-4) |
| **devops** | DevOps Engineer | /dr-plan, /dr-do, /dr-compliance |
| **writer** | Content Writer | /dr-write, /dr-archive (Step 0.5 + final docs), /dr-prd |
| **editor** | Content Editor | /dr-edit, /dr-qa (content) |
| **skill-creator** | Skill/Agent/Command Creator | /dr-addskill |
| **optimizer** | Framework Optimizer | /dr-optimize, /dr-archive (Step 0.5 health-check) |
| **librarian** | Knowledge Base Librarian | /dr-dream |
| **security** | Security Analyst | /dr-design, /dr-qa, /dr-compliance |
| **sre** | Site Reliability Engineer | /dr-design, /dr-qa, /dr-archive (Step 0.5 postmortem) |
| **tester** | Platform QA Tester | /dr-qa, /dr-do (verification) |
| **researcher** | Structured External Research | /dr-prd (Phase 1.3), /dr-do (Gap Discovery) |
| **peer-reviewer** | Adversarial Peer Reviewer (Layer 2/3 fallback) | /dr-verify (cross-Claude-family fallback subagent) |

Agent files: `$HOME/.claude/agents/{name}.md` (18 agents)

### Agent Loading Rules

1. Each command specifies which agent to load
2. Agent loads its mandatory and optional skills
3. Agent reads relevant `datarim/` state files
4. Only one primary agent per command execution
5. Consilium skill can assemble multiple agents for panel discussions

### Minimum Agent Set by Complexity

Not all agents are needed for every task. Load the minimum set to conserve context tokens:

| Level | Required Agents | Optional |
|-------|----------------|----------|
| **L1** | developer | reviewer, tester |
| **L2** | planner, developer | reviewer, architect, tester |
| **L3** | planner, architect, developer, reviewer | strategist, security, tester, writer, editor |
| **L4** | planner, architect, developer, reviewer, strategist | devops, security, sre, tester, writer, editor, compliance |

For content-focused tasks (articles, research, documentation), writer and editor replace developer and reviewer as primary agents.

Consilium panels (L3-4) draw from the full roster as needed.

---

## Skills

Skills are reusable knowledge modules loaded on demand. They provide rules, patterns, and guidelines.

### Loading Hierarchy

**Always loaded (mandatory):**
- `datarim-system.md` — Core workflow rules, path resolution, file locations

**Loaded per stage:**
- `ai-quality.md` — TDD, decomposition, cognitive load (loaded by: developer, planner)
- `compliance.md` — 7-step hardening workflow (loaded by: compliance agent)
- `security.md` — Auth, input validation, data protection (loaded by: reviewer, security agent)
- `testing.md` — Testing pyramid, mocking rules (loaded by: developer, reviewer)
- `performance.md` — Optimization patterns (loaded by: architect, sre)
- `tech-stack.md` — Stack selection by project type (loaded by: planner, architect)
- `utilities.md` — Native shell recipes for common operations (loaded when needed)

**Specialized skills:**
- `consilium.md` — Multi-agent panel discussions (loaded by: /dr-design for L3-4)
- `discovery.md` — Requirements discovery interview (loaded by: /dr-prd)
- `evolution.md` — Framework self-update rules (loaded by: /dr-archive Step 0.5 via reflecting skill, /dr-optimize)
- `reflecting.md` — Review-phase workflow: lessons learned, evolution proposals with Class A/B gate, health-metrics check, follow-up-task detection (loaded by: /dr-archive Step 0.5, internal only)
- `writing.md` — Content creation and editorial workflow (loaded by: writer, editor)
- `dream.md` — Knowledge base maintenance rules (loaded by: librarian)
- `go-to-market.md` — SEO, analytics, ad campaigns, landing pages, launch checklists (loaded on demand)
- `factcheck.md` — Fact verification for publications (loaded by: editor, on demand)
- `humanize.md` — AI text pattern removal (loaded by: editor, on demand)
- `visual-maps.md` — Mermaid workflow diagrams: pipeline routing, stage flows, agent-skill-command graphs (loaded on demand for navigation)
- `telegram-publishing.md` — Telegram Bot API publishing rules, caption limits, discussion group comments (loaded on demand)
- `project-init.md` — Project scaffolding: creates CLAUDE.md, docs/, datarim/ structure for new projects (loaded by: /dr-init when project intent detected)
- `research-workflow.md` — Structured research methodology, checklist, tool selection, gap discovery protocol (loaded by: researcher)
- `publishing.md` — Multi-platform publishing rules, formatting, platform limits, workflow (loaded by: writer, on demand)
- `datarim-doctor.md` — Schema and migration semantics for /dr-doctor (thin one-liner contract, YAML description schema) (loaded by: /dr-doctor, /dr-init self-heal, /dr-archive line-format gate)
- `file-sync-config.md` — Pre-flight checklist + ignore patterns for file-sync (Syncthing/rclone/rsync) protecting git working trees and venv/build (loaded on demand for sync setup)
- `frontend-ui.md` — Frontend UI checklist: CSS specificity, dark/light themes, visual testing, mobile responsiveness, i18n parity (loaded when editing HTML/CSS)
- `infra-automation.md` — Infrastructure ops: SSH batch execution, health checks, network debugging, pre-migration inventory (loaded for server ops)

Skill files: `$HOME/.claude/skills/{name}.md` (41 skills, 10 with supporting fragment directories)

> **v1.16.0 addition:** `cta-format.md` — canonical CTA "Next Step" block specification, loaded by `planner`, `architect`, `developer`, `reviewer`, `compliance` agents. Defines structure, separators, primary marker, multi-task menu (Variant B), and FAIL-Routing variant. Source: TUNE-0032.

---

## Datarim State Directory

Each project maintains two directories at the project root (created by `/dr-init`):

```
datarim/                          # Workflow state (LOCAL — in .gitignore)
├── activeContext.md              # Active Tasks mirror only (≤30 lines, TUNE-0071 v2)
├── tasks.md                     # Active one-liner index (thin schema)
├── backlog.md                   # Pending one-liner index (thin schema)
├── projectbrief.md              # Project overview
├── productContext.md             # Product requirements
├── systemPatterns.md            # Architecture patterns
├── techContext.md               # Technology context
├── style-guide.md               # Code style guide
├── prd/                         # Product Requirements Documents
├── tasks/                       # Task documentation
├── creative/                    # Design phase documents
├── reflection/                  # Reflection documents
├── qa/                          # QA reports
├── reports/                     # Compliance/diagnostic reports
└── docs/                        # Evolution log

documentation/                    # Project documentation (COMMITTED to git)
└── archive/                     # Completed task archives
    ├── infrastructure/          # INFRA-* tasks
    ├── web/                     # WEB-* tasks
    ├── development/             # DEV-* tasks
    ├── content/                 # CONTENT-* tasks
    ├── research/                # RESEARCH-* tasks
    ├── agents/                  # AGENT-* tasks
    ├── benchmarks/              # BENCH-* tasks
    ├── devops/                  # DEVOPS-* tasks
    ├── framework/               # TUNE-*, ROB-* tasks
    ├── maintenance/             # MAINT-* tasks
    ├── finance/                 # FIN-* tasks
    ├── qa/                      # QA-* tasks
    ├── optimized/               # Framework optimizer backups
    ├── cancelled/               # Cancelled tasks (TUNE-0071 v2)
    └── general/                 # Unmatched prefixes
```

**Two-layer architecture:** `datarim/` is ephemeral workflow state (added to `.gitignore`). `documentation/archive/` is long-term project documentation (committed to git). See [Getting Started](docs/getting-started.md) for details.

### Path Resolution Rule

Before writing ANY file to `datarim/`:
1. Check if `datarim/` exists in the current directory
2. If not, walk UP the directory tree until found
3. If not found anywhere: **STOP** — only `/dr-init` may create `datarim/`

---

## Commands

| Command | Stage | Description |
|---------|-------|-------------|
| `/dr-init` | Initialize | Create task, pick from backlog, or **scaffold a new project**. Assess complexity, set up `datarim/` |
| `/dr-prd` | Requirements | Generate PRD with discovery interview |
| `/dr-plan` | Planning | Detailed implementation plan with strategist gate |
| `/dr-design` | Design | Architecture exploration with consilium |
| `/dr-do` | Execution | Implement the plan: TDD for code, structured iteration for other work |
| `/dr-qa` | Quality | Multi-layer verification (PRD, design, plan, output quality) |
| `/dr-verify` | Verification | Standalone self-verification (on-demand). Tri-layer: Layer 1 deterministic floor + Layer 2 cross-model peer-review (DeepSeek default) + Layer 3 native runtime dispatch. Findings-only mode. |
| `/dr-compliance` | Hardening | 7-step post-QA hardening |
| `/dr-archive` | Archive | Reflection (Step 0.5: lessons learned + framework evolution proposals) + complete task + update backlog + reset context |
| `/dr-status` | Utility | Check current task and backlog status |
| `/dr-continue` | Utility | Resume from last checkpoint |
| `/dr-write` | Content | Create written content — articles, docs, research, posts |
| `/dr-edit` | Content | Editorial review — fact-check, humanize, style, polish |
| `/dr-publish` | Content | Adapt and publish content to multiple platforms |
| `/dr-addskill` | Extension | Create or update skills, agents, commands with web research |
| `/dr-doctor` | Maintenance | Diagnose and repair Datarim operational files — migrate to thin one-liner schema, externalize task descriptions, abolish progress.md |
| `/dr-dream` | Maintenance | Knowledge base maintenance: organize, lint, index, cross-reference |
| `/dr-optimize` | Maintenance | Audit framework, prune unused, merge duplicates, sync docs |
| `/dr-plugin` | Extension | Manage opt-in plugin system (list/enable/disable/sync/doctor — TUNE-0101 v1.23.0). Manifest-driven runtime symlinks, snapshot/rollback, dependency-graph + skill-registry health checks |
| `/dr-orchestrate run` | Plugin | Self-driving Datarim pipeline runner (v2.5.0). Phase 1 lean rule-based tmux runner; Phase 2 adds multi-backend subagent inference (coworker → claude → codex) for unknown prompts, autonomy L1 → L2 (assisted), flock-race-safe cooldown, audit schema v2. v2.5.0 adds bot-interaction interface (OpenAPI 3.1 + adnanh/webhook reference impl + HMAC-SHA256 / Redis pub/sub outbound emitter, gated activation). Install via `dr-plugin enable dr-orchestrate`. Security floor: whitelist + 0x1b escape-block + 500 ms micro + 60 s decision cooldown + 5-violations/hr 1 h pane block. JSONL audit, hash-only credentials. |
| `/dr-help` | Utility | List all commands with descriptions and usage guidance |
| `/factcheck` | Standalone | Fact-check articles and posts before publication |
| `/humanize` | Standalone | Remove AI writing patterns from text |

Command files: `$HOME/.claude/commands/{name}.md` (22 commands core + 1 plugin)

### /dr-verify (on-demand, tri-layer architecture)

Manual self-verification command (post-completion review of any pipeline artifact). **Tri-layer architecture (cheapest-first, fail-fast):**

1. **Layer 1 — Deterministic floor.** `dev-tools/dr-verify-floor.sh` — pure shell pipeline (AC coverage grep, file-touched audit, test-presence parse, shellcheck). Zero LLM cost; runs in seconds.
2. **Layer 2 — Cross-model peer-review.** `coworker ask --provider {peer-provider} --task-id <ID>` — adversarial reviewer in clean external context. Vendor-neutral via the coworker abstraction.

   **Provider auto-resolves** via 6-step resolution chain (`dev-tools/resolve-peer-provider.sh`):
   - **zero-flag UX** when no provider configured anywhere — chain falls through to subagent dispatch
   - resolution chain order: CLI → per-project datarim-config → per-user XDG datarim-config → coworker `--profile code` default → cross-Claude-family fallback → same-model isolated last resort
   - cross-Claude-family fallback dispatches `agents/peer-reviewer.md` at `model: sonnet` (covered by Claude subscription, no external API key required)
   - audit-log records `peer_review_provider`, `peer_review_mode`, `peer_review_provider_source_layer` for unambiguous trace
3. **Layer 3 — Native runtime dispatch.** Claude 3-agent parallel (reviewer + tester + security) is canonical; Codex single-prompt is `[experimental]` fallback retained for parity.

Findings carry an explicit `source_layer` tag (`floor` / `peer_review` / `dispatch`) and dedupe across layers prefers earlier-source findings. NOT a replacement for `/dr-qa` — `/dr-qa` is a manual single-agent multi-layer review; `/dr-verify` is a runtime-dispatch structured-findings loop.

**Когда использовать:**
- Перед merge / archive — sanity check на final PRD/plan/code state
- Retrospective validation — проверка завершённой задачи на пропущенные gaps
- Fast pre-merge gating: `--floor-only` (Layer 1 only, zero LLM cost)
- Не входит в default pipeline (manual on-demand only — automated post-step hook is a deferred future evolution)

**Args:** `/dr-verify {TASK-ID} [--stage={prd,plan,do,all}] [--max-iter=N] [--no-fix] [--floor-only] [--peer-provider={deepseek,groq,openrouter,...}] [--runtime={claude,codex}] [--external-verifier=PASS] [--cost-cap=N]`

**Findings schema:** `{finding_id, source_layer ∈ {floor, peer_review, dispatch}, artifact_ref, ac_criteria[], severity (high/medium/low), category (correctness/completeness/consistency/safety), drift_subtype (optional), evidence (file_quote/test_output/absent), suggested_fix, check_name (Layer 1), peer_review_provider (Layer 2)}`. 7 validator rules + 3 severity anchors + 4 category anchors + 3 evidence types + auto-discard + verifiability + secret redaction. Canonical in `skills/self-verification.md` § Findings Schema.

**Verdict logic:** BLOCKED (≥1 high) / CONDITIONAL (≥1 medium, 0 high) / PASS (only low or empty).

**Audit log:** `datarim/qa/verify-{task-id}-{stage}-{iter}.md` (append-only, `chmod a-w` post-write). Header carries `source_layer_breakdown: {floor: N, peer_review: M, dispatch: K}` for tri-layer provenance.

**`coworker --task-id <ID>` propagation MANDATORY at Layer 2.** Without it the prospective-rate / token-cost tooling (`dev-tools/measure-prospective-rate.sh` + `dev-tools/measure-invocation-token-cost.sh`) cannot filter logs by task.

### Verification tagging at archive time

`/dr-archive` Step 2 instructs the operator to fill the `verification_outcome` block in the archive frontmatter (canonical schema in `templates/archive-template.md`):

```yaml
verification_outcome:
  caught_by_verify: <int>     # high/medium gaps caught BEFORE /dr-archive
  missed_by_verify: <int>     # gaps that escaped to a post-archive follow-up
  false_positive: <int>       # findings triaged as not real
  n_a: <bool>                 # true when /dr-verify was not run
  dogfood_window: <window-id> # operator-supplied grouping key
```

Aggregator `dev-tools/measure-prospective-rate.sh --since <YYYY-MM-DD>` walks all `archive-*.md` files, computes `caught_per_5_tasks`, and emits a `decision_hint` for the next pipeline gate. The `verification_outcome` block is the single source of truth for the prospective measurement campaign.

**Status:** tri-layer canonical, findings-only at all layers (no auto-fix). Cross-link: skill `skills/self-verification.md` · floor script `dev-tools/dr-verify-floor.sh` · template `templates/archive-template.md`.

---

## Plugin System (v1.23.0+, TUNE-0101)

Datarim ships with a built-in `datarim-core` set (skills/agents/commands/templates) and an opt-in plugin mechanism for everything beyond. Plugins are local directories (or git URLs in a future phase) shaped as `{plugin-id}/{plugin.yaml, skills/, agents/, commands/, templates/}`. The `/dr-plugin` CLI manages the active set:

```bash
/dr-plugin list                              # active set + bootstrap on first run
/dr-plugin enable /path/to/my-plugin         # absolute path to source dir
/dr-plugin disable my-plugin
/dr-plugin sync                              # reconcile runtime ↔ manifest (idempotent)
/dr-plugin doctor [--fix]                    # 9 health checks
```

**Manifest:** `datarim/enabled-plugins.md` — single source of truth (one entry per active plugin: `id`, `source`, `version`, `enabled_at`, optional `depends_on`, `overrides`, `file_inventory`).

**Symlink layout:** plugin files link into `~/.claude/<category>/<plugin-id>/<basename>` for namespace isolation. Files declared under `overrides:` install at root position `~/.claude/<category>/<basename>` to win the local-overlay precedence. Root-position install is conflict-checked against existing symlinks and regular files.

**Safety:**
- Pre-mutation snapshot of `runtime/` + `manifest.md` on every `enable` (FIFO cap `DR_PLUGIN_SNAPSHOT_MAX=50`; age-based purge after `DR_PLUGIN_SNAPSHOT_AGE_DAYS=30`).
- mkdir-based atomic lock (`DR_PLUGIN_LOCK_TIMEOUT=60`) — `flock` is not assumed (macOS portability).
- Validation gate rejects: invalid plugin id (must be kebab-case, ≤32 chars), embedded credentials in URLs, CRLF in `plugin.yaml` (security), path traversal (`..`), schema_version drift (only `1` accepted).
- Critical-core overrides (`evolution`, `datarim-system`, `pre-archive-check`) emit a warning to stderr and proceed — operator decides.

**Doctor checks (9):** manifest-syntax, inventory-consistency, broken-symlinks, orphan-files, override-integrity, dependency-graph (DFS cycle/dangling), git-state (uncommitted manifest), snapshot-cleanup (>30d), skill-registry (frontmatter `name:` ↔ basename — closes Skill-tool resolution gap).

**Personal additions vs plugins:** `~/.claude/local/{skills,agents,commands,templates}/` (gitignored overlay) is for one-off personal stuff. `/dr-plugin` is for shareable, versioned extensions distributed as a unit.

---

## Self-Evolution

Datarim improves itself through `/dr-archive` Step 0.5 (the `reflecting` skill):

1. After each task, the agent analyzes what worked and what didn't
2. Proposes updates to skills, agents, or this CLAUDE.md
3. **Human approval required** — no automatic modifications
4. Changes logged in `datarim/docs/evolution-log.md`

### Validation Discipline

New schema validations (frontmatter shape, token budget gates, intent-layer grep, cross-reference checks, etc.) ship as **standalone scripts** under `dev-tools/check-*.sh` or `dev-tools/measure-*.sh`, invoked by `/dr-qa`, `/dr-compliance`, or CI. They MUST NOT be added as new branches inside `datarim-doctor.sh`, whose primary concern is operational-file migration (progress.md retirement, schema bumps, etc.).

Rule: **orthogonal concerns get orthogonal tools.** Content validation has a different lifetime, invocation context, and test surface than ops-file migration; coupling the two grows the migrator into a 1000+-line monolith and slows future schema changes.

Each new validator follows a simple contract:

- Pure shell, no dependencies beyond what bash + grep + the framework's own `dev-tools/` provide.
- Single `--check` mode: exit 0 = PASS, exit 1 = FAIL. Optional `--report` for human-readable detail.
- Self-documents target scope in the script header.
- Referenced directly by PRD AC text (so the gate is falsifiable; see `skills/evolution.md` § Pattern: Split-Architecture Metrics).

---

## Critical Rules

1. **Datarim is truth** — `datarim/` for workflow state, `documentation/archive/` for completed task archives
2. **Task ID required** — All reports must include task ID in filename
3. **Path resolution first** — Always find `datarim/` before writing
4. **No absolute paths** — Use `$HOME/.claude/` or project-relative paths only
5. **Context before code** — Gather requirements before implementing
6. **One thing at a time** — Implement one method/stub per iteration
7. **Human in the loop** — Evolution proposals need approval
8. **Rules are stack- AND history-agnostic** — Task IDs MUST NOT appear in `skills/*.md`, `agents/*.md`, `commands/*.md`, `templates/*.md`. Provenance lives in `docs/evolution-log.md`, `documentation/archive/`, git log. Gates: `scripts/stack-agnostic-gate.sh` (stack terms) and `scripts/task-id-gate.sh` (history). Contracts: `skills/evolution/stack-agnostic-gate.md` and `skills/evolution/history-agnostic-gate.md`.

---

## Workspace Discipline (multi-agent)

Workflow-state directories shared by multiple agent sessions follow Step 0.1 semantics from `commands/dr-archive.md`: foreign-task-ID hunks belong to parallel sessions and are NOT blockers; only the current task's own forgotten hunks (or unattributed hunks) block. Apply the recipe (`git add -p` or blob-swap) at Step 0.1.3. Project source trees remain single-agent and treat any uncommitted change as a STOP. Source: TUNE-0044 (2026-04-29).

### Canonical-First Development for Runtime Artefacts

Any code that lives in `code/datarim/{scripts,tests,skills,agents,commands,templates}/` MUST be edited in the canonical Datarim repo, never via `~/.claude/<scope>/` (which under v1.17+ symlink-mode is a directory-symlink to canonical). Editing through the symlink works mechanically (same inode) but obscures `git diff` visibility in the canonical repo and risks loss-on-rebuild. Any tool that writes directly to `~/.claude/<scope>/` outside the install pipeline is a defect — the canonical repo is the single source of truth.

---

## Security Mandate

> **Status:** mandatory for every Datarim artifact (skill, agent, command, template, script, doc).
> **Origin:** corporate security audit, 2026-04-28 (6 findings: 2× HIGH command injection, 4× MEDIUM SSH/credentials/supply-chain). Full audit log: `documentation/archive/security/findings-2026-04-28.md`.
> **Authority:** RFC 2119 keywords (MUST / MUST NOT / SHOULD / MAY) apply throughout.
> **Single source of truth:** `skills/security-baseline.md` § S1–S9 — full rules, suppression policy, counter-example fence syntax, standards mapping. This CLAUDE.md section is the entry point.

### Threat model (one paragraph)

Datarim ships skills, templates, agents, and commands that AI agents copy into runtime and execute, often with elevated privileges (root SSH, OAuth tokens with write scope, package installation). A vulnerable line in a shipped script is replicated into every consumer's production runbook. A documented `curl | bash` recipe in a skill becomes the canonical install pattern across the ecosystem. **Every shipped artifact is production code under attack.**

### Rule clusters (details in `skills/security-baseline.md`)

- **S1** — Shell scripts and embedded shell blocks (strict mode, quoting, input regex, heredoc terminators, no eval/curl|bash, no SSH `StrictHostKeyChecking=no`, `shellcheck` clean)
- **S2** — Python and python-fenced blocks (no `shell=True`, atomic mode-0o600 credential writes via `O_EXCL`, no `eval`/`pickle.loads`/`yaml.load`, `requests verify=True`, SHA-256+, `bandit -ll -ii` clean)
- **S3** — Credentials, secrets, tenant identifiers (no hardcoded IDs, generic env-var paths via `${PROJECT_CREDS_DIR}`, secrets via env/Vault/prompt only, `.gitignore` coverage, rotation policy on accidental commit)
- **S4** — Supply chain (no `curl | bash`, hash-pinned installs, GitHub Actions pinned to commit SHA + explicit `permissions:`, SBOM, signed releases, SLSA L2, Dependabot/Renovate). Consumer-side verify recipe: [`docs/release-verification.md`](docs/release-verification.md) (canonical) + [`skills/release-verify.md`](skills/release-verify.md) (AI-agent loadable entry point). Implementation: `.github/workflows/release.yml` (cosign sign-blob + `actions/attest-build-provenance` for SLSA L2).
- **S5** — Markdown documentation as executable instructions (placeholders not real IDs, never prescribe unsafe patterns, `<!-- security:counter-example -->` fence syntax for teaching counter-examples)
- **S6** — Repo hygiene (LICENSE, SECURITY.md, CODE_OF_CONDUCT, CONTRIBUTING, CODEOWNERS, dependabot.yml, branch + tag protection)
- **S7** — CI verification gate (`shellcheck`, `bandit`, `semgrep`, `gitleaks`, `trufflehog`, `actionlint`, `zizmor`, `osv-scanner`, regression `bats`)
- **S8** — Standards mapping (ASVS v5 / SOC 2 CC / ISO 27001 Annex A / CIS Controls v8 — see `docs/standards-mapping.md`)
- **S9** — Drift, evolution, incident response (no relaxation without architect approval; new findings → rule update + regression test within 7 days)

### CI verification (consumer projects)

Every Datarim-managed project SHOULD run `templates/security-workflow.yml` (drop-in) or call `Arcanada-one/datarim/.github/workflows/reusable-security.yml@<tag>` (preferred). Local dry-run: run `templates/security-workflow.yml` locally (security audit is integrated into `/dr-qa`).

**Source:** corporate audit findings 2026-04-28 + research baseline `~/arcanada/datarim/insights/INSIGHTS-security-baseline-oss-cli-2026.md`.

---

## Documentation Taxonomy Mandate

> **Status:** mandatory for every Datarim-managed repo and product site.
> **Single source of truth:** `skills/diataxis-docs.md` (4 closed categories — tutorials / how-to / reference / explanation; mapping table; exemption list; anti-patterns).

Every Datarim-managed repo and product site MUST organise its documentation per **Diátaxis** (https://diataxis.fr) — four orthogonal categories:

- **Tutorials** — learning-oriented (newcomer end-to-end).
- **How-to** — problem-solving (task recipes).
- **Reference** — information-oriented (lookup, catalogue).
- **Explanation** — understanding-oriented (background, why).

Closed set: `faq`, `glossary`, `troubleshooting`, `examples`, `overview`, `samples` are mappable to one of the four categories — never separate top-level types. See `skills/diataxis-docs.md` § Mapping Table.

Mandate level:

1. **New repos / sites** — `/dr-init` scaffolds `docs/{tutorials,how-to,reference,explanation}/` by default with category README stubs from `templates/docs-diataxis/`.
2. **Existing repos** — soft audit via `/dr-optimize` Step 6a (filesystem-presence + threshold ≥3 docs files); on drift the audit proposes `INFRA-* — Diátaxis docs reorg для <repo>` in backlog.
3. **Stack-agnostic** — taxonomy contract only. SSG/CMS choice (any static-site generator) is per-project and outside the mandate.
4. **Hard CI gate deferred** — backlog item activates the same detector at `exit 1` after the mandate is adopted on ≥3 live consumers.
5. **Exemptions** — research-only repos, archive-only repos, Obsidian vault PARA, single-file inbox notes, temporary scratch paths. See `skills/diataxis-docs.md` § Exemption List.
6. **Brand layer is out of scope** — Datarim defines the taxonomy structure (four categories + exemptions). Slogans, footers, brand assets are ecosystem-specific and defined by the consumer's own CLAUDE.md.

---

## Public Surface Hygiene Mandate (cross-link)

> **Status:** mandatory for every Datarim consumer that ships public packages (npm / PyPI / Docker Hub / web). The canonical text lives in the **consumer's** ecosystem `CLAUDE.md` — Datarim ships the contract surface (forbidden-regex set + retroactive-sweep recipe), not the canonical text, because the regex set is ecosystem-owned (consumer's task-prefix registry) and audit-tagged per consumer.
> **Reference consumer:** `/Users/ug/arcanada/CLAUDE.md` § Public Surface Hygiene Mandate (Arcanada ecosystem canonical).

Datarim framework's contribution:

- **`dev-tools/public-surface-lint.sh`** — pure-shell linter that walks `--paths` and greps for forbidden references (task IDs, PRD-/creative-/plans-/insights- patterns, internal-datarim-repo paths) loaded from a sibling `.regex` file. Single `--check` mode: exit 0 = clean, exit 1 = found. Per `dev-tools/` orthogonal-tool rule — content validation has different lifetime and invocation context than ops-file migration, so the lint lives outside `datarim-doctor.sh`.
- **`dev-tools/public-surface-forbidden.regex`** — machine-readable regex set; consumers extend it with their own task-prefix list at install time (one line per pattern, `#` for comments).
- **Pre-publish gate hook** — invoked by `/dr-archive` Step 2 when the task touched any artifact published to an external registry (closed set: npm / PyPI / Docker Hub / web). Hard block on findings.

Consumers MUST mirror the canonical mandate text and the forbidden-regex extension in their own ecosystem `CLAUDE.md` before publishing public packages; the lint script and the regex file are contract surfaces, not substitutes for the operator-readable rules text. Conflict resolution with Supreme Directive: Law 1 (Non-Harm) overrides re-publish urgency — if a strip introduces a security regression, escalate per the consumer's FB-rules instead of patch-bumping.

---

## Autonomous Agent Operating Rules (cross-link)

> **Status:** mandatory for every Datarim consumer that hosts AI agents. The full ruleset lives in the **consumer's** ecosystem `CLAUDE.md` — Datarim ships the operating-rules contract surface, not the canonical text, because the canonical text is ecosystem-owned and audit-tagged per consumer.
> **Reference consumer:** `/Users/ug/arcanada/CLAUDE.md` § Autonomous Agent Operating Rules Mandate (Arcanada ecosystem canonical; source: TUNE-0185 Phase 4 + `Projects/Datarim/datarim/insights/INSIGHTS-TUNE-0185-fb-rules.md`).

Datarim framework's contribution:

- **`plugins/dr-orchestrate/rules/fb-rules.yaml`** — machine-readable policy block (FB-1..FB-8 with `enforcement_layer` / `tier` / `default_action` / `reversibility_required` / `audit_required` / `conflicts_with_law` + `hard_gated_actions:` list).
- **`plugins/dr-orchestrate/scripts/rules_loader.sh`** — `load_fb_policy()` and `load_fb_hard_gates()` entry points; orthogonal to the prompt-pattern `load()` stream (separate schema, separate consumers — do not merge).
- **Pipeline gates** — `/dr-prd` discovery decision-matrix enforces FB-2; `/dr-design` consilium enforces FB-3; `/dr-qa` + `/dr-verify` pre-archive enforce FB-7; reflection enforces FB-4 (`reason` field in audit log).
- **Conflict resolution** — Supreme Directive (Laws 1-5) > Autonomous Agent Operating Rules > AAL Mandate > project-specific mandates. `hard_gated_actions:` NEVER auto-execute regardless of FB-5.

Consumers MUST mirror the canonical FB-rules text and the enforcement-mapping table in their own ecosystem `CLAUDE.md` before enabling the `dr-orchestrate` plugin; the YAML policy block is a contract surface, not a substitute for the operator-readable rules text.

---

## Defensive Invariants

When a script's textual output is contractually paired with its exit code or internal state (e.g. "BLOCKED" message ↔ exit 1, "OK" message ↔ exit 0, "applied" flag ↔ side-effect performed), insert a precondition guard immediately before emitting the wording:

```bash
if [ "$flag" -ne <expected> ]; then
    echo "ERROR: internal invariant violated: <description>" >&2
    exit 2
fi
echo "<wording bound to flag>"
```

The guard catches the class of refactor regressions where future edits decouple state from wording (e.g. a new branch sets the flag but skips the wording, or vice versa). Cost is two lines; the saving is not shipping a contradictory message that misleads operators about whether a pipeline is blocked. Apply to any state machine where wording is a named contract surface (gates, classifiers, commit gates, deploy guards). Do not apply to incidental log lines.

---

## Documentation

For external library and API documentation, use `context7` MCP server when available. It provides token-efficient access to up-to-date documentation. If `context7` is not available, fall back to `WebFetch` / `WebSearch`.

---

## Project-Specific Configuration

Everything below this line is project-specific. When installing Datarim in a new project, keep everything above and customize below.

---

### What This Project Is

<!-- Describe your project here -->

### Tech Stack

<!-- List your technology stack -->

### Conventions

<!-- Project-specific coding conventions -->

### Key Files

<!-- Important files and their purposes -->

### Task Prefix Registry

Project-local task prefixes for `datarim-doctor.sh` archive routing. The doctor walks up the directory tree, parses the first `## Task Prefix Registry` section it finds, and resolves the prefix to its Archive Subdir. Universal area prefixes (`INFRA`, `WEB`, `DEV`, `DEVOPS`, `CONTENT`, `RESEARCH`, `AGENT`, `BENCH`, `MAINT`, `FIN`, `QA`, `SEC`, `TUNE`, `ROB`) live in the Datarim runtime and apply automatically — do not repeat them here.

Schema: `| Prefix | Project | Archive Subdir |`. Archive Subdir MUST match `^[a-z][a-z0-9-]*$` (single path component, no `/`, no `..`).

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| DATA | Datarim framework | framework |

> `TUNE` is already a universal area prefix in the runtime (archive subdir `framework/`); no row needed. Adding a new project prefix here propagates automatically to `/dr-archive` routing — no Datarim framework change required.
