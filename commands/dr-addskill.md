---
name: dr-addskill
description: Create or update Datarim skills, agents, and commands. Researches best practices, audits existing components, and generates properly formatted artifacts in the correct scope (project or user level).
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
    - Skills: YAML frontmatter (name, description) + structured markdown sections
    - Agents: Frontmatter (name, description, model) + Role statement + Capabilities + Context Loading
    - Commands: Frontmatter (name, description, argument-hint) + Instructions + Next Steps
    - Keep descriptions under 250 characters for reliable skill triggering
    - Refer to existing skills in Context Loading where relevant
8.  **PRESENT**: Show the user:
    - What files will be created/updated (paths + content)
    - Why this structure was chosen
    - How to invoke the new capability
    - Wait for approval before writing any files
9.  **APPLY**: After approval:
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

## Next Steps
- New skill needs testing? → Ask user to invoke it and review output
- Updating Datarim source? → Update counts in CLAUDE.md, README.md, dr-help.md
- Need more domain expertise? → Run additional web research
