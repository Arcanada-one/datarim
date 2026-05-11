---
name: dr-addskill
description: Create or update Datarim skills, agents, and commands. Researches best practices, audits existing components, generates artifacts.
argument-hint: [description of needed capability]
allowed-tools: Read Write Edit Grep Glob Bash WebSearch WebFetch Agent
effort: high
---

# /dr-addskill — Create or Update Skills, Agents, Commands

**Role**: Skill Creator Agent
**Source**: `$HOME/.claude/agents/skill-creator.md`

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/skill-creator.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/evolution.md` (Framework modification rules)
3.  **PARSE REQUEST**: Analyze `$ARGUMENTS` to understand:
    - What domain or capability is needed?
    - What concrete actions should the new skill/agent perform?
    - Is this a skill, agent, command, or combination?
4.  **RESEARCH**: Use WebSearch and WebFetch to find:
    - Best practices for the target domain (e.g., "interior design technical specifications")
    - Existing Claude Code skills or agent patterns for similar domains
    - Community skills at github.com/anthropics/skills, github.com/VoltAgent/awesome-agent-skills
    - Download and analyze 2-3 relevant examples
5.  **AUDIT EXISTING FRAMEWORK**:
    - List all current skills, agents, and commands in the target scope
    - Check if the user's need is already covered (fully or partially)
    - Determine: Create new? Update existing? Extend + supplement?
6.  **DETERMINE SCOPE** (where to install):
    - If user said "global" / "user-level" / "for all projects" → `$HOME/.claude/`
    - If project has `.claude/skills/` with at least one `.md` file → project `.claude/`
    - If project has `.claude/` directory → project `.claude/`
    - Otherwise → ask the user
7.  **DESIGN**: Create the artifact(s) following Datarim conventions:
    - Skills: YAML frontmatter (name, description, [model for task-skills]) + structured markdown sections
    - Agents: Frontmatter (name, description, **model** [REQUIRED]) + Role statement + Capabilities + Context Loading
    - Commands: Frontmatter (name, description, argument-hint) + Instructions + Next Steps
    - Keep descriptions under 250 characters for reliable skill triggering
    - Refer to existing skills in Context Loading where relevant
    - **Determine model per `$HOME/.claude/skills/datarim-system.md` § Model Assignment Convention:**
      - Agents: REQUIRED (opus / sonnet / haiku)
      - Task skills: REQUIRED (opus / sonnet / haiku)
      - Reference skills (rules/patterns only): omit `model` (inherits from caller)
    - Document the rationale for chosen model in the proposal you present to the user
8.  **PRESENT**: Show the user:
    - What files will be created/updated (paths + content)
    - Why this structure was chosen
    - How to invoke the new capability
    - Wait for approval before writing any files
8a. **TDD FOR SKILL CREATION** (mandatory for discipline-enforcing skills, recommended for technique skills):

    **RED — Baseline failure** *before* writing any skill prose:
    - Construct a test scenario that exercises the failure mode the skill is meant to prevent (or the technique it is meant to teach).
    - Run the scenario against a fresh agent context with the candidate skill **not** loaded — observe whether it fails as expected.
    - Capture the agent's rationalizations *verbatim* (e.g., "too simple to need a test", "I'll just check this one thing first"). These become inputs to the GREEN step.
    - For discipline-enforcing skills, build pressure into the scenario: combined time pressure + sunk cost + authority conflict expose rationalizations that simple scenarios miss.

    **GREEN — Minimal skill addressing observed failures:**
    - Write the smallest skill body that answers each captured rationalization explicitly. Don't generalize to hypothetical failures — answer the ones you observed.
    - Each rationalization gets a Red-Flag row in the skill body: the excuse on the left, the corrective response on the right.

    **REFACTOR — Bulletproofing pass:**
    - Re-run the test scenario with the skill loaded. If the agent still rationalizes around it, identify the new loophole, add a counter, repeat.
    - Make the spirit-vs-letter principle explicit when the skill is being followed-but-not-honored: *"Violating the letter is violating the spirit."*
    - Stop when an additional iteration produces no new rationalizations.

    **Cancel-and-restart trigger:** if you wrote skill prose without observing a baseline failure first, the skill is hypothesis-only. Delete it and run the RED step before re-attempting.

    For pure-reference skills (rules / constants / cross-reference indexes) the RED step is replaced by a retrieval gap test: ask a fresh agent the questions the skill is meant to answer; record gaps; write the skill to fill those gaps.

9.  **APPLY**: After approval:
    - **Stack-agnostic gate (MANDATORY when target scope is `$HOME/.claude/{skills,agents,commands,templates}/`):** load `$HOME/.claude/skills/evolution/stack-agnostic-gate.md` and run gate over each new/updated artifact's full text (script form: `scripts/stack-agnostic-gate.sh <target>`). FAIL → do NOT write; return to user with the matched keywords and either (a) reword stack-neutral, or (b) install into a project-scoped `.claude/` dir instead.
    - Create necessary directories (`mkdir -p .claude/skills .claude/agents .claude/commands`)
    - Write the files
    - If updating Datarim source repo, also update CLAUDE.md counts and tables
10. **CONFIRM**: Tell the user:
    - What was installed and where
    - How to use it (slash command, auto-trigger, or both)
    - Whether a `/reload` or new session is needed

## Scope Rules

| Condition | Install to |
|-----------|-----------|
| User said "global" or "user-level" | `$HOME/.claude/` |
| Project has `.claude/skills/*.md` | Project `.claude/` |
| Project has `.claude/` dir | Project `.claude/` |
| No project `.claude/` | Ask user, default to project `.claude/` |

## Quality Criteria for Generated Skills

- **Description is a trigger, not a summary** — write it for the model: "when should I fire?"
- **Don't state the obvious** — focus on what pushes Claude out of its default behavior
- **Don't railroad** — give goals and constraints, not prescriptive step-by-step
- **Include a Gotchas section** — highest-signal content for the model
- **Keep SKILL.md under 500 lines** — move detailed reference to supporting files
- **Front-load key use case in description** — truncated after 250 chars

## Next Steps (CTA)

After skill creation, the skill-creator agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-addskill`:**

- New skill needs testing → primary "ask user to invoke and review output" + alternative `/dr-qa {TASK-ID}` if part of TUNE task
- Updating Datarim source → primary "update counts in CLAUDE.md, README.md, dr-help.md" + reminder to curate via `scripts/curate-runtime.sh`
- Need more domain expertise → alternative `/dr-prd {TASK-ID}` (research-phase) before iterating
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks.
