---
name: project-init
description: Project scaffolding — creates CLAUDE.md, documentation/, datarim/ for new or existing projects. Loaded by /dr-init when project intent is detected.
current_aal: 1
target_aal: 2
---

# Project Init — Scaffolding Skill

> **Loaded by:** `/dr-init` (Step 0, when project intent detected)
> **Purpose:** Create a standardized project structure with CLAUDE.md, documentation, and Datarim workflow state.

## When This Skill Activates

`/dr-init` loads this skill when the user's input contains project creation signals:
- Keywords: "create project", "new project", "init project", "scaffold project"
- Update keywords: "update project structure", "re-scaffold", "обнови структуру проекта" <!-- allow-non-ascii: literal-russian-intent-trigger-phrase-required-by-classifier -->
- Russian: "создай проект", "новый проект", "инициализируй проект" <!-- allow-non-ascii: literal-russian-intent-trigger-phrases-required-by-classifier -->
- Pattern: `/dr-init create project "Name"`

If none of these signals are present, `/dr-init` follows the standard task flow.

## Scaffolding Flow

### Step 1: Gather Project Info

Ask the user (if not already provided in the prompt):

1. **Project name** — used in CLAUDE.md header and directory name
2. **One-line description** — what the project does
3. **Project type** — determines tech stack (see `$HOME/.claude/skills/tech-stack/SKILL.md` § Stack Selection Decision Tree)

If the user provided enough context in the initial prompt, extract these values without asking. Only ask for what is missing.

### Step 2: Determine Target Directory

- **Default:** current working directory
- **If user specified a name:** create `<name>/` in current directory (kebab-case)
- **If inside an Obsidian vault or monorepo:** respect the existing structure (e.g., `Projects/<Name>/code/`)

Verify the target exists or create it.

### Step 3: Determine Tech Stack

Load `$HOME/.claude/skills/tech-stack/SKILL.md` and match the project type to the required stack. This determines:
- `.gitignore` contents
- Build commands for CLAUDE.md
- Dependencies and toolchain

If the project type is unclear, ask the user. If the project is documentation/research-only, skip tech stack detection.

### Step 4: Create Project Structure

Create the following structure following the **Diátaxis Documentation Taxonomy Mandate** (`skills/diataxis-docs/SKILL.md`). **Idempotency rule:** check if each file/directory exists before creating. If it exists, skip it and report "skipped: already exists". Never overwrite existing files.

```
<project-root>/
├── CLAUDE.md                    # From template: $HOME/.claude/templates/project-claude-md.md
├── .gitignore                   # Standard for detected stack
│
├── documentation/                        # Diátaxis 4-category split (mandate per skills/diataxis-docs/SKILL.md)
│   ├── tutorials/               # Learning-oriented (newcomer end-to-end)
│   │   └── README.md            # From template: $HOME/.claude/templates/documentation-diataxis/tutorials/README.md
│   ├── how-to/                  # Problem-solving (task recipes)
│   │   ├── README.md            # From template: $HOME/.claude/templates/documentation-diataxis/how-to/README.md
│   │   ├── testing.md           # Legacy stub mapped to how-to per Diátaxis
│   │   ├── deployment.md        # Legacy stub mapped to how-to
│   │   └── gotchas.md           # Legacy stub mapped to how-to
│   ├── reference/               # Information-oriented (lookup, catalogue)
│   │   ├── README.md            # From template: $HOME/.claude/templates/documentation-diataxis/reference/README.md
│   │   └── architecture.md      # Legacy stub mapped to reference (system map)
│   └── explanation/             # Understanding-oriented (background, why)
│       └── README.md            # From template: $HOME/.claude/templates/documentation-diataxis/explanation/README.md
│
├── documentation/ephemeral/              # Transient working material (may be gitignored or committed per preference)
│   ├── plans/                   # Implementation plans
│   ├── research/                # Research notes
│   └── reviews/                 # QA reports and reviews
│
├── datarim/                     # Workflow state (created via standard /dr-init logic)
│   ├── backlog.md               # From template: $HOME/.claude/templates/backlog-template.md
│   ├── activeContext.md          # Active task tracking
│   └── tasks.md                 # Task details
│
└── documentation/               # Long-term archives (committed to git)
    └── archive/                 # Completed task archives
```

### Step 4.5: Secrecy-Aware Scaffolding

Some projects have a **secret core** — a proprietary algorithm, encoding scheme, compression mechanism, or private model weights that must NOT appear on any public surface. For these, the scaffold must be mechanism-free from the first commit, and the secrecy gate must be emitted **at scaffold time**, not bolted on after a leak is caught.

**Detect the secrecy signal.** Enter secrecy-aware mode when the operator brief carries EITHER:

- an explicit `secrecy: <domain>` annotation (e.g. `secrecy: algorithm`), OR
- a secret-core keyword: `secret core`, `secret algorithm`, `proprietary algorithm`, `encoding scheme`, `compression mechanism`, `mechanism must stay secret` (and their equivalents in the brief's language).

If neither is present, skip this step — the scaffold is unchanged (byte-identical to the non-secret path).

**In secrecy-aware mode:**

1. **Mechanism-free reference stub.** Write `documentation/reference/architecture.md` from the **secrecy-aware variant** in `templates/project-docs-stubs.md`: its Overview / Components / Data Flow / Security Model bodies carry `[REDACTED — see CLAUDE.md § Secrecy]` instead of a "describe the system" TODO.
2. **No mechanism on the public surface.** Do NOT populate any file under the public Diátaxis surface (`documentation/{tutorials,how-to,reference,explanation}/`) or any `README*` with the secret mechanism's lexicon. The secret lives only in the private code and, if needed, in `documentation/ephemeral/` (excluded from the public surface). This is the direct root-cause fix for the scaffold-leak pattern (precedent: a QA blocker on an earlier secrecy-bearing project — the scaffold committed the full mechanism into `documentation/reference/architecture.md` before secrecy was codified).
3. **Emit the secrecy gate now.** When filling CLAUDE.md (Step 5), include the conditional `## Secrecy` block from the template (the `<!-- SECRECY-BLOCK … -->` section) — the secrecy declaration plus the README-tolerant grep gate — so the gate exists at scaffold time, not as a post-hoc fix.

### Step 5: Fill CLAUDE.md Template

Read `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-claude-md.md` and replace placeholders:

| Placeholder | Source |
|-------------|--------|
| `__PROJECT_NAME__` | From user input (Step 1) |
| `__ONE_LINE_DESCRIPTION__` | From user input (Step 1) |
| `__DATE__` | Current date (YYYY-MM-DD) |
| `__TECH_STACK__` | From tech-stack.md detection (Step 3) |
| `__BUILD_COMMANDS__` | From tech-stack.md detection (Step 3) |
| `__GITIGNORE_PATTERNS__` | From tech-stack.md detection (Step 3) |

**Diátaxis taxonomy in CLAUDE.md.** When the project's CLAUDE.md is generated, include a one-liner reference to `documentation/{tutorials,how-to,reference,explanation}/` so that future contributors discover the mandate from the project root, not only from Datarim framework docs.

For placeholders the agent cannot fill (components, terminology, gotchas), leave them as `[TODO: ...]` markers for the user.

**Secrecy block (secrecy-aware mode only).** If Step 4.5 detected a secrecy signal, keep the template's conditional `## Secrecy` block (marked `<!-- SECRECY-BLOCK … -->`) and fill its project-specific mechanism terms into the grep gate. Otherwise drop the block entirely — a non-secret project gets no Secrecy section.

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

Created (Diátaxis 4-category split per skills/diataxis-docs/SKILL.md):
  ✓ CLAUDE.md
  ✓ documentation/tutorials/README.md         (learning-oriented)
  ✓ documentation/how-to/README.md            (problem-solving)
  ✓ documentation/how-to/testing.md           (legacy stub mapped to how-to)
  ✓ documentation/how-to/deployment.md        (legacy stub mapped to how-to)
  ✓ documentation/how-to/gotchas.md           (legacy stub mapped to how-to)
  ✓ documentation/reference/README.md         (information-oriented)
  ✓ documentation/reference/architecture.md   (legacy stub mapped to reference — system map)
  ✓ documentation/explanation/README.md       (understanding-oriented)
  ✓ documentation/ephemeral/{plans,research,reviews}/
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
2. Scan for existing documentation/ — create only missing stubs
3. Scan for existing datarim/ — skip entirely (already initialized)
4. Create only what is missing from the standard structure

This allows updating old projects to the new structure incrementally.

## What This Skill Does NOT Do

- Does not install dependencies via the project's package manager — that is the user's responsibility
- Does not create source code files — only project infrastructure
- Does not modify existing files — only creates new ones
- Does not run CI/CD setup — that is a separate task
- Does not add `--dry-run` or `--force` flags (future enhancement)
- In secrecy-aware mode, does NOT write the secret mechanism to any public Diátaxis file or `README*` — mechanism-bearing reference stubs are `[REDACTED]` (see Step 4.5)
