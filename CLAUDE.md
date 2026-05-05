# Datarim — Universal Iterative Workflow Framework

> **Version:** 1.22.0
> **Framework:** Datarim (Датарим) provides structured rules, agents, skills, and commands for iterative project execution via Claude Code — software development, research, documentation, legal work, project management, and any task that benefits from a phased workflow.
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

Agent files: `$HOME/.claude/agents/{name}.md` (17 agents)

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

Skill files: `$HOME/.claude/skills/{name}.md` (27 skills, 3 with supporting fragment directories)

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
| `/dr-help` | Utility | List all commands with descriptions and usage guidance |
| `/factcheck` | Standalone | Fact-check articles and posts before publication |
| `/humanize` | Standalone | Remove AI writing patterns from text |

Command files: `$HOME/.claude/commands/{name}.md` (20 commands)

---

## Self-Evolution

Datarim improves itself through `/dr-archive` Step 0.5 (the `reflecting` skill):

1. After each task, the agent analyzes what worked and what didn't
2. Proposes updates to skills, agents, or this CLAUDE.md
3. **Human approval required** — no automatic modifications
4. Changes logged in `datarim/docs/evolution-log.md`

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
