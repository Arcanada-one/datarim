---
name: project-init
description: Project scaffolding — creates CLAUDE.md, docs/, datarim/ structure for new or existing projects. Loaded by /dr-init when project intent is detected.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Project Init — Scaffolding Skill

> **Loaded by:** `/dr-init` (Step 0, when project intent detected)
> **Purpose:** Create a standardized project structure with CLAUDE.md, documentation, and Datarim workflow state.

## When This Skill Activates

`/dr-init` loads this skill when the user's input contains project creation signals:
- Keywords: "create project", "new project", "init project", "scaffold project"
- Update keywords: "update project structure", "re-scaffold", "обнови структуру проекта"
- Russian: "создай проект", "новый проект", "инициализируй проект"
- Pattern: `/dr-init create project "Name"`

If none of these signals are present, `/dr-init` follows the standard task flow.

## Scaffolding Flow

### Step 1: Gather Project Info

Ask the user (if not already provided in the prompt):

1. **Project name** — used in CLAUDE.md header and directory name
2. **One-line description** — what the project does
3. **Project type** — determines tech stack (see `$HOME/.claude/skills/tech-stack.md` § Stack Selection Decision Tree)

If the user provided enough context in the initial prompt, extract these values without asking. Only ask for what is missing.

### Step 2: Determine Target Directory

- **Default:** current working directory
- **If user specified a name:** create `<name>/` in current directory (kebab-case)
- **If inside an Obsidian vault or monorepo:** respect the existing structure (e.g., `Projects/<Name>/code/`)

Verify the target exists or create it.

### Step 3: Determine Tech Stack

Load `$HOME/.claude/skills/tech-stack.md` and match the project type to the required stack. This determines:
- `.gitignore` contents
- Build commands for CLAUDE.md
- Dependencies and toolchain

If the project type is unclear, ask the user. If the project is documentation/research-only, skip tech stack detection.

### Step 4: Create Project Structure

Create the following structure. **Idempotency rule:** check if each file/directory exists before creating. If it exists, skip it and report "skipped: already exists". Never overwrite existing files.

```
<project-root>/
├── CLAUDE.md                    # From template: $HOME/.claude/templates/project-claude-md.md
├── .gitignore                   # Standard for detected stack
│
├── docs/                        # Durable project documentation (committed to git)
│   ├── architecture.md          # From template: $HOME/.claude/templates/project-docs-stubs.md § architecture
│   ├── testing.md               # From template: § testing
│   ├── deployment.md            # From template: § deployment
│   └── gotchas.md               # From template: § gotchas
│
├── docs/ephemeral/              # Transient working material (may be gitignored or committed per preference)
│   ├── plans/                   # Implementation plans
│   ├── research/                # Research notes
│   └── reviews/                 # QA reports and reviews
│
├── datarim/                     # Workflow state (created via standard /dr-init logic)
│   ├── backlog.md               # From template: $HOME/.claude/templates/backlog-template.md
│   ├── backlog-archive.md       # From template: $HOME/.claude/templates/backlog-archive-template.md
│   ├── activeContext.md          # Active task tracking
│   ├── tasks.md                 # Task details
│   └── progress.md              # Progress tracking
│
└── documentation/               # Long-term archives (committed to git)
    └── archive/                 # Completed task archives
```

### Step 5: Fill CLAUDE.md Template

Read `$HOME/.claude/templates/project-claude-md.md` and replace placeholders:

| Placeholder | Source |
|-------------|--------|
| `__PROJECT_NAME__` | From user input (Step 1) |
| `__ONE_LINE_DESCRIPTION__` | From user input (Step 1) |
| `__DATE__` | Current date (YYYY-MM-DD) |
| `__TECH_STACK__` | From tech-stack.md detection (Step 3) |
| `__BUILD_COMMANDS__` | From tech-stack.md detection (Step 3) |
| `__GITIGNORE_PATTERNS__` | From tech-stack.md detection (Step 3) |

For placeholders the agent cannot fill (components, terminology, gotchas), leave them as `[TODO: ...]` markers for the user.

### Step 6: Initialize Git (if needed)

- If `.git/` does not exist in the target directory: run `git init`
- If `.gitignore` was created: ensure `datarim/` is listed
- Do NOT create an initial commit automatically — let the user review first

### Step 7: Post-Scaffold Report

Output a summary:

```
Project scaffolded: <project-name>
Location: <target-path>
Stack: <detected-stack or "none (documentation project)">

Created:
  ✓ CLAUDE.md
  ✓ docs/architecture.md
  ✓ docs/testing.md
  ✓ docs/deployment.md
  ✓ docs/gotchas.md
  ✓ docs/ephemeral/{plans,research,reviews}/
  ✓ datarim/ (workflow state)
  ✓ documentation/archive/
  ✓ .gitignore

Skipped (already existed):
  - <list of skipped files, if any>

Next steps:
  1. Review and customize CLAUDE.md — fill in [TODO] placeholders
  2. Review .gitignore
  3. git add -A && git commit -m "scaffold: initial project structure"
  4. /dr-init <first task description>  — start your first task
```

## Idempotency Rules

1. **Never overwrite** an existing file — even if the template has changed
2. **Always create** missing directories silently
3. **Report** every skipped file so the user knows what was preserved
4. **Update mode:** if user says "update project structure" or "re-scaffold", apply the same logic — create only what is missing, skip what exists

## Integration with Existing Projects

When run in an existing project (that already has some files):

1. Scan for existing CLAUDE.md — if found, skip it
2. Scan for existing docs/ — create only missing stubs
3. Scan for existing datarim/ — skip entirely (already initialized)
4. Create only what is missing from the standard structure

This allows updating old projects to the new structure incrementally.

## What This Skill Does NOT Do

- Does not install dependencies via the project's package manager — that is the user's responsibility
- Does not create source code files — only project infrastructure
- Does not modify existing files — only creates new ones
- Does not run CI/CD setup — that is a separate task
- Does not add `--dry-run` or `--force` flags (future enhancement)
