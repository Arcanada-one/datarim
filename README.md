# Datarim

**A self-evolving SDLC framework that gives AI agents a structured development process — from requirements to production.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What is Datarim?

AI coding agents today operate without methodology. They receive a prompt, generate
code, and move on. There is no requirements analysis, no design phase, no quality
assurance, no reflection. The result is inconsistent quality, skipped phases, and
zero institutional learning. Every task starts from scratch, repeating the same
mistakes the agent made yesterday.

Datarim fixes this by providing a complete SDLC pipeline purpose-built for AI agents.
It includes 11 specialized agents, 13 reusable skills, and 11 commands that guide
development through a structured process: requirements gathering, planning, design,
implementation, quality assurance, compliance, reflection, and archival. The pipeline
is complexity-aware — a one-line typo fix does not go through the same process as a
database migration. Datarim routes each task through exactly the stages it needs.

Built exclusively for Claude Code, Datarim is universal. It works for any project,
any programming language, any tech stack. There are no hardcoded paths, no vendor
lock-in, no project-specific assumptions. And it is self-evolving: after every
completed task, the framework analyzes what worked, what failed, and proposes
improvements to its own agents, skills, and rules. The name "Datarim" comes from
*data + rim* — the edge where structured data meets creative engineering.

---

## Pipeline

### Full Pipeline (Mermaid)

```mermaid
graph LR
    init["init"] --> prd["prd"]
    prd --> plan["plan"]
    plan --> design["design"]
    design --> do["do"]
    do --> qa["qa"]
    qa --> compliance["compliance"]
    compliance --> reflect["reflect"]
    reflect --> archive["archive"]

    style init fill:#4a9eff,stroke:#333,color:#fff
    style prd fill:#ff6b6b,stroke:#333,color:#fff
    style plan fill:#ffa94d,stroke:#333,color:#fff
    style design fill:#ffd43b,stroke:#333,color:#000
    style do fill:#69db7c,stroke:#333,color:#000
    style qa fill:#da77f2,stroke:#333,color:#fff
    style compliance fill:#e599f7,stroke:#333,color:#000
    style reflect fill:#74c0fc,stroke:#333,color:#000
    style archive fill:#868e96,stroke:#333,color:#fff
```

### Complexity Routing (ASCII)

Not every task needs every stage. Datarim routes tasks based on complexity:

```
L1 (Quick Fix):    init ──────────────────────────── do ──── reflect ── archive
L2 (Enhancement):  init ── [prd] ── plan ──────────── do ── [qa] ── reflect ── archive
L3 (Feature):      init ── prd ── plan ── design ──── do ── qa ── [compliance] ── reflect ── archive
L4 (Major):        init ── prd ── plan ── design ── phased-do ── qa ── compliance ── reflect ── archive
```

Stages in `[brackets]` are conditional — included when the agent determines they add value.

### Complexity Routing Table

| Level | Name | Scope | LOC Estimate | Pipeline |
|-------|------|-------|-------------|----------|
| L1 | Quick Fix | 1 file | < 50 | `init` → `do` → `reflect` → `archive` |
| L2 | Enhancement | 2–5 files | < 200 | `init` → `[prd]` → `plan` → `do` → `[qa]` → `reflect` → `archive` |
| L3 | Feature | 5–15 files | 200–1000 | `init` → `prd` → `plan` → `design` → `do` → `qa` → `[compliance]` → `reflect` → `archive` |
| L4 | Major | 15+ files | > 1000 | `init` → `prd` → `plan` → `design` → `phased-do` → `qa` → `compliance` → `reflect` → `archive` |

---

## Features

- **11 specialized agents** — planner, architect, developer, reviewer, compliance,
  code-simplifier, strategist, devops, writer, security, and SRE. Each agent has a
  defined role, capabilities, and the stages where it operates.

- **13 reusable skills** — modular knowledge units that agents load on demand,
  covering everything from testing methodology to security hardening to AI text
  humanization.

- **9-stage complexity-aware pipeline** — tasks flow through exactly the stages they
  need. No unnecessary ceremony for simple fixes, full rigor for major changes.

- **Self-evolving framework** — after every task, the reflect stage analyzes outcomes
  and proposes improvements to agents, skills, and framework rules. The framework
  gets better with use.

- **Consilium: multi-agent panel discussions** — for critical decisions, assemble a
  panel of relevant agents to debate trade-offs and reach a recommendation before
  committing to a direction.

- **Discovery: structured requirements interviews** — systematic elicitation of
  requirements through guided questions, ensuring nothing important is missed before
  planning begins.

- **Multi-layer QA** — verification happens at multiple stages: PRD validation,
  design review, plan verification, code review, and compliance checking. Defects
  are caught early, not in production.

- **Native shell utilities** — no external MCP server dependencies required. All
  core functionality works through Claude Code's built-in tools and shell access.

- **Fact-checking and AI text humanization** — specialized skills for content work:
  verify claims against sources, remove AI writing artifacts, preserve the author's
  natural voice.

- **Strategic advisor gate** — before committing to major work, the strategist agent
  evaluates value, risk, and cost. Not every technically interesting idea deserves
  implementation resources.

- **Universal compatibility** — works for any project, any language, any stack.
  Python, TypeScript, Rust, Go, Java — the framework adapts to what you are building.

---

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- **Recommended:** [context7](https://github.com/upstash/context7) MCP server for
  token-efficient documentation access (reduces context usage when looking up library
  docs)

---

## Installation

### macOS / Linux

```bash
git clone https://git.veritasarcana.ai/root/datarim.git
cd datarim
chmod +x install.sh
./install.sh
```

The installer copies agents, skills, commands, and templates to `~/.claude/` and
confirms what was installed.

### Windows (WSL / Git Bash)

```bash
# From WSL or Git Bash terminal:
git clone https://git.veritasarcana.ai/root/datarim.git
cd datarim
./install.sh
```

The same installer works under WSL and Git Bash. Native PowerShell is not supported.

### Manual Installation

If you prefer to install manually or need to customize the locations:

```bash
mkdir -p ~/.claude/{agents,skills,commands,templates}
cp agents/*.md ~/.claude/agents/
cp skills/*.md ~/.claude/skills/
cp commands/*.md ~/.claude/commands/
cp templates/*.md ~/.claude/templates/
```

### Activate in Your Project

```bash
cp CLAUDE.md /path/to/your/project/
```

The `CLAUDE.md` file contains the framework rules that Claude Code reads on startup.
The file has two sections:

1. **Framework section** (top) — pipeline definitions, agent roster, skill
   references, and behavioral rules. Do not modify this section.
2. **Project section** (bottom) — your project description, tech stack, conventions,
   and custom rules. Customize this freely.

---

## Quick Start

```bash
# Navigate to your project
cd your-project

# Copy the framework rules into your project root
cp /path/to/datarim/CLAUDE.md .

# Edit the project-specific section at the bottom of CLAUDE.md
# Add your project description, tech stack, conventions

# Start Claude Code
claude

# Initialize a task — Datarim assigns complexity and routes the pipeline
/dr-init Add user authentication with JWT

# The framework tells you what stage comes next.
# For an L3 task, the pipeline would be:
/dr-prd        # Generate product requirements document
/dr-plan       # Create implementation plan
/dr-design     # Explore architectural decisions
/dr-do         # Implement with TDD
/dr-qa         # Run quality assurance checks
/dr-reflect    # Analyze what worked and what to improve
/dr-archive    # Archive the completed task

# Check progress at any time
/dr-status

# Resume after a break
/dr-continue
```

Each command guides you through its stage. The framework tracks state between
commands and tells you what to do next.

---

## Agents

| Agent | Role | Primary Stages |
|-------|------|----------------|
| **Planner** | Breaks tasks into phases, estimates complexity, defines acceptance criteria | `plan` |
| **Architect** | Designs system architecture, evaluates trade-offs, defines interfaces | `design`, `consilium` |
| **Developer** | Implements code following TDD, applies coding standards, writes tests | `do` |
| **Reviewer** | Reviews code for quality, correctness, and adherence to plan | `qa` |
| **Compliance** | Validates implementation against PRD, checks for regressions | `compliance` |
| **Code Simplifier** | Reduces complexity, eliminates duplication, improves readability | `do`, `qa` |
| **Strategist** | Evaluates value/risk/cost, advises on priorities, gates major work | `init`, `prd` |
| **DevOps** | Handles deployment, CI/CD, infrastructure, and environment configuration | `do`, `compliance` |
| **Writer** | Creates documentation, README files, API docs, user guides | `do`, `reflect` |
| **Security** | Audits for vulnerabilities, reviews auth flows, checks dependencies | `qa`, `compliance` |
| **SRE** | Evaluates reliability, scalability, monitoring, and operational readiness | `design`, `compliance` |

Agents are loaded on demand. A quick fix (L1) may only activate the Developer.
A major migration (L4) may involve all eleven agents across different stages.

---

## Skills

| Skill | Purpose | Loaded By |
|-------|---------|-----------|
| **datarim-system** | Core framework logic — pipeline routing, state management, complexity assessment | All agents |
| **ai-quality** | TDD methodology, stubbing patterns, cognitive load management | Developer, Reviewer |
| **compliance** | PRD revalidation, regression checking, post-QA hardening | Compliance |
| **security** | Vulnerability scanning, dependency audit, auth flow review | Security |
| **testing** | Test strategy, coverage analysis, test organization patterns | Developer, Reviewer |
| **performance** | Profiling, optimization patterns, benchmark methodology | Architect, Developer |
| **tech-stack** | Technology evaluation, compatibility checking, migration guidance | Architect, Strategist |
| **utilities** | Shell helpers, file operations, environment detection | All agents |
| **consilium** | Multi-agent panel assembly, structured debate, consensus building | Any (on demand) |
| **discovery** | Requirements elicitation, stakeholder interviews, scope definition | Planner, Strategist |
| **evolution** | Framework self-improvement, metric tracking, change proposals | Reflect stage |
| **factcheck** | Claim extraction, source verification, accuracy scoring | Writer |
| **humanize** | AI artifact removal, voice preservation, natural language patterns | Writer |

Skills are modular. Each is a standalone Markdown file that agents load when they need
specific capabilities. You can add custom skills by placing `.md` files in
`~/.claude/skills/`.

---

## Commands

| Command | Stage | Description |
|---------|-------|-------------|
| `/dr-init` | Initialize | Start a new task. Assigns complexity level (L1–L4), routes the pipeline, creates task context. |
| `/dr-prd` | Requirements | Generate a Product Requirements Document. Analyzes the problem, defines scope, success criteria, and constraints. |
| `/dr-plan` | Planning | Create a detailed implementation plan. Breaks work into phases, estimates effort, identifies risks. |
| `/dr-design` | Design | Explore architectural decisions. Evaluates alternatives, documents trade-offs, defines interfaces. |
| `/dr-do` | Implementation | Write code following TDD. Implements the plan, writes tests first, follows project conventions. |
| `/dr-qa` | Quality Assurance | Run quality checks. Code review, test verification, standard compliance, coverage analysis. |
| `/dr-compliance` | Compliance | Post-QA hardening. Validates implementation against PRD, checks for regressions, security audit. |
| `/dr-reflect` | Reflection | Analyze the completed task. What worked, what failed, what to improve. Proposes framework updates. |
| `/dr-archive` | Archive | Archive the task. Stores context, decisions, and outcomes for future reference. |
| `/dr-status` | Any | Check current task status, progress through the pipeline, and pending actions. |
| `/dr-continue` | Any | Resume work from the last checkpoint. Restores context and picks up where you left off. |

Commands are sequential within a pipeline but you can always check `/dr-status` or
`/dr-continue` at any point.

---

## Complexity Levels

### L1 — Quick Fix

**Scope:** Single file, under 50 lines of code.
**Pipeline:** `init` → `do` → `reflect` → `archive`
**Example tasks:**
- Fix a typo in README
- Update a dependency version in package.json
- Correct a CSS color value
- Fix a broken import path

L1 tasks skip requirements, planning, design, QA, and compliance. The fix is trivial
enough that these stages would add overhead without value. Reflection still happens —
even small fixes can reveal patterns worth noting.

### L2 — Enhancement

**Scope:** 2–5 files, under 200 lines of code.
**Pipeline:** `init` → `[prd]` → `plan` → `do` → `[qa]` → `reflect` → `archive`
**Example tasks:**
- Add input validation to a login form
- Implement a new API endpoint for an existing resource
- Add error handling to a file upload function
- Create a configuration option for an existing feature

L2 tasks get a lightweight plan and optional PRD and QA. The scope is small enough
that a brief plan suffices, but large enough that jumping straight to code risks
missing edge cases.

### L3 — Feature

**Scope:** 5–15 files, 200–1000 lines of code.
**Pipeline:** `init` → `prd` → `plan` → `design` → `do` → `qa` → `[compliance]` → `reflect` → `archive`
**Example tasks:**
- Implement OAuth2 authentication
- Build a real-time notification system
- Create a data export pipeline with multiple formats
- Add role-based access control

L3 tasks go through the full pipeline. Requirements need formal documentation, design
decisions need explicit trade-off analysis, and QA needs thorough coverage. Compliance
is included when the feature touches security, data handling, or external integrations.

### L4 — Major

**Scope:** 15+ files, over 1000 lines of code.
**Pipeline:** `init` → `prd` → `plan` → `design` → `phased-do` → `qa` → `compliance` → `reflect` → `archive`
**Example tasks:**
- Migrate from monolith to microservices
- Rewrite the authentication system
- Implement a plugin architecture
- Build a multi-tenant data isolation layer

L4 tasks use phased implementation. The work is broken into multiple implementation
cycles, each with its own do-qa loop. This prevents the "big bang" problem where
thousands of lines are written before any testing happens. Compliance is always
required at L4.

---

## Consilium

Consilium is Datarim's multi-agent panel discussion system. When a decision is too
important for a single agent's perspective, you assemble a panel of relevant agents
to debate the trade-offs.

**How it works:**

1. A question is posed (e.g., "Should we use PostgreSQL or MongoDB for this service?")
2. Relevant agents are assembled (e.g., Architect + Security + SRE)
3. Each agent presents their analysis from their domain perspective
4. Agents respond to each other's points
5. The panel produces a structured recommendation with dissenting opinions noted

**Example:**

```
Question: Database choice for the new analytics service
Panel: Architect, Security, SRE

Architect: PostgreSQL — strong consistency, mature ecosystem, JSONB for flexibility.
Security: PostgreSQL — better audit logging, row-level security, proven encryption.
SRE: PostgreSQL preferred, but consider read replicas early — analytics queries
     will compete with transactional load.

Recommendation: PostgreSQL with read replica architecture from day one.
Dissent: None.
```

Consilium is available at any stage via the `consilium` skill. Use it for:
- Technology selection decisions
- Architecture pattern choices
- Security model design
- Migration strategy evaluation
- Any decision with significant irreversibility

---

## Self-Evolution

Datarim improves itself over time. This is not automatic — it requires human approval
at every step.

### How it works

1. **Reflect** — After every completed task, the `/dr-reflect` command analyzes what
   happened. What stages added value? What was skipped unnecessarily? Where did the
   pipeline slow down without benefit? What patterns emerged?

2. **Propose** — Based on the reflection, the evolution skill generates concrete
   proposals: update a skill's instructions, adjust an agent's behavior, add a new
   pattern to CLAUDE.md, modify complexity routing thresholds.

3. **Approve** — Every proposal is presented to the human operator. Nothing changes
   without explicit approval. The human can accept, reject, or modify any proposal.

4. **Log** — Accepted changes are logged in `evolution-log.md` with timestamps,
   rationale, and the task that triggered the change. This creates an audit trail
   of how the framework evolved and why.

### What evolves

- **Agent instructions** — if an agent consistently misses something, its instructions
  are updated to address the gap.
- **Skill content** — if a skill lacks coverage for a recurring scenario, it gets
  expanded.
- **Complexity thresholds** — if tasks are being over- or under-classified, the
  routing rules are adjusted.
- **Pipeline stages** — if a stage is consistently skipped at a certain level, the
  routing is updated to reflect actual practice.
- **CLAUDE.md rules** — if project-specific patterns emerge, they are codified into
  the framework rules.

### What does not evolve

- The Five Laws (non-harm, human priority, constrained self-preservation, control
  and termination, transparency and enforcement) are immutable.
- The requirement for human approval of changes is permanent.
- The audit trail requirement is permanent.

---

## Project Configuration

When you copy `CLAUDE.md` into your project, you get a file with two distinct
sections:

### Framework Section (Do Not Modify)

The top section contains:

- **Pipeline definition** — the nine stages and their routing rules
- **Agent roster** — all eleven agents with their roles and stage assignments
- **Skill references** — the thirteen skills and when they are loaded
- **Behavioral rules** — how agents interact, when to escalate, what requires
  human approval
- **Complexity classification** — LOC thresholds, file count criteria, routing logic

This section is maintained by the Datarim project. When you update Datarim, this
section gets updated. Do not add project-specific content here.

### Project Section (Customize Freely)

The bottom section is yours. Add:

```markdown
## Project Description
Brief description of what your project does.

## Tech Stack
- Language: TypeScript
- Runtime: Node.js 20
- Framework: Express
- Database: PostgreSQL 16
- Testing: Vitest

## Conventions
- Use functional style, avoid classes
- All functions must have JSDoc comments
- Error handling: Result type, not exceptions
- File naming: kebab-case

## Custom Rules
- Never modify migration files after they are committed
- All API endpoints must have OpenAPI annotations
- Feature flags for all new user-facing functionality
```

Agents read this section to understand your project's context and conventions. The
more specific you are, the better the agents perform.

---

## Philosophy

### Process Over Hope

Quality software does not come from hoping the AI gets it right. It comes from
structured methodology — requirements before code, design before implementation,
verification before deployment. Datarim does not make AI agents smarter. It makes
them methodical. A methodical agent with average capability outperforms a brilliant
agent with no process.

### Complexity-Aware

Not every task deserves a PRD. Not every change needs a design review. Treating a
typo fix with the same rigor as a database migration wastes time and erodes trust in
the process. Datarim matches process intensity to task complexity. Simple tasks get
simple process. Complex tasks get full rigor. The framework routes automatically
based on scope and impact.

### Self-Evolving

A framework that cannot learn is a framework that stagnates. Development practices
change. Team patterns emerge. New categories of mistakes appear. Datarim's reflection
and evolution mechanism ensures the framework adapts to reality rather than demanding
reality adapt to it. Every completed task is an opportunity to improve the process.

### Universal

Datarim has no opinion about your tech stack. It does not care if you write Python
or Rust, use React or Svelte, deploy to AWS or a bare-metal server. The framework
operates at the methodology level — requirements, planning, design, implementation,
verification — which is independent of technology choices. You bring the stack.
Datarim brings the process.

### Human in the Loop

AI agents propose. Humans decide. This is not a limitation — it is a design
principle. Agents can analyze, recommend, and implement, but irreversible decisions
require human approval. Framework evolution requires human approval. Deployment
requires human approval. The framework is explicit about where the human gate is
and why it exists.

---

## Directory Structure

```
datarim/
  agents/            # Agent definition files (11 agents)
  skills/            # Skill definition files (13 skills)
  commands/          # Command definition files (11 commands)
  templates/         # Task and document templates
  docs/              # Extended documentation
  CLAUDE.md          # Framework rules (copy to your project)
  install.sh         # Automated installer
  LICENSE            # MIT license
  README.md          # This file
```

---

## Contributing

Contributions are welcome. To contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes following the existing file patterns
4. Test by installing locally and running through a task pipeline
5. Submit a pull request with a clear description of what changed and why

### Guidelines

- **New agents:** Follow the structure in existing agent `.md` files. Define role,
  capabilities, primary stages, and interaction patterns.
- **New skills:** Follow the structure in existing skill `.md` files. Define purpose,
  when to load, and the knowledge content.
- **New commands:** Follow the structure in existing command `.md` files. Define
  stage, prerequisites, actions, and outputs.
- **Framework changes:** Update `CLAUDE.md`, relevant docs, and this README.
- **Keep it universal:** No project-specific content, no hardcoded paths, no
  technology assumptions.

---

## License

MIT — see [LICENSE](LICENSE)

---

Built for agents that deserve a better process.
