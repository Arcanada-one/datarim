# Datarim System — Command and Archive Rules

## Namespace Rules

### Command Prefix: `/dr-`

All Datarim commands use the `/dr-` prefix.

**Why:** Claude Code already reserves built-in commands such as `/init`, `/status`, `/continue`, and `/plan`.

### Reserved Names

Do not create Datarim commands with these names:

`/init`, `/status`, `/continue`, `/plan`, `/clear`, `/help`, `/model`, `/compact`, `/config`, `/exit`, `/login`, `/resume`

### Naming Convention

- always prefix with `/dr-`
- use lowercase kebab-case
- keep the name short

## Archive Area Mapping

When archiving a task, map the prefix to the destination subdirectory.

**Universal area prefixes** (stack-agnostic, owned by Datarim runtime):

| Prefix | Area Subdirectory |
|--------|------------------|
| `INFRA` | `infrastructure/` |
| `WEB` | `web/` |
| `CONTENT` | `content/` |
| `RESEARCH` | `research/` |
| `AGENT` | `agents/` |
| `BENCH` | `benchmarks/` |
| `DEV` | `development/` |
| `DEVOPS` | `devops/` |
| `TUNE` | `framework/` |
| `ROB` | `framework/` |
| `MAINT` | `maintenance/` |
| `FIN` | `finance/` |
| `QA` | `qa/` |
| `SEC` | `security/` |
| *(unknown)* | resolved via Project Prefix lookup, else `general/` |

**Project prefixes** (ecosystem- or project-specific) are NOT defined in the Datarim runtime. They are declared by the consumer in the nearest `CLAUDE.md` `## Task Prefix Registry` section and resolved by `scripts/datarim-doctor.sh` walking up from the Datarim root. See `skills/datarim-system/task-identity-and-context.md` § Project Prefix Resolution.

Archive path:

```text
documentation/archive/{area}/archive-{task_id}.md
```

## Project Setup

`/dr-init` supports two modes, selected automatically via intent detection (Step 0):

### Task Mode (default)

When `/dr-init` initializes a task:

1. Create `datarim/` at the project root.
2. Create `documentation/archive/` for long-term archives.
3. Add `datarim/` to `.gitignore`.
4. Keep `documentation/` committed.

This allows parallel local workflow state with committed shared archives.

### Project Mode (scaffolding)

When `/dr-init` detects project creation intent (keywords: "create project", "new project", "создай проект", etc.):

1. Load `$HOME/.claude/skills/project-init.md`.
2. Create full project structure: `CLAUDE.md`, `docs/`, `docs/ephemeral/`, `datarim/`, `documentation/archive/`, `.gitignore`.
3. Fill `CLAUDE.md` from template `$HOME/.claude/templates/project-claude-md.md` with project-specific placeholders.
4. Create doc stubs from template `$HOME/.claude/templates/project-docs-stubs.md`.
5. Detect tech stack via `$HOME/.claude/skills/tech-stack.md` and apply to templates.
6. Idempotent: skip existing files, create only what is missing.

Project mode exits after scaffolding — it does not continue to the task flow.

## Count Verification Rule

Any plan or documentation that references component counts (skills, agents, commands, templates) **must verify from disk** before writing. Do not copy counts from existing documentation — they drift.

```bash
# Authoritative counts
ls $HOME/.claude/skills/*.md | wc -l    # skills
ls $HOME/.claude/agents/*.md | wc -l    # agents
ls $HOME/.claude/commands/*.md | wc -l  # commands
ls $HOME/.claude/templates/*.md | wc -l # templates
```

Source: prior incident — plan stated "24→25 skills" but actual count was 20→21. README had stale counts (24 skills, 5 templates). Disk-first verification catches this.

## Critical Rules

1. `datarim/` is workflow truth; `documentation/archive/` is archive truth.
2. Every report filename includes the task ID.
3. `documentation/tasks/` must not exist.
4. `activeContext.md` must stay current.
5. Backlog uses the active + archive split.
6. Path resolution happens before any write.
7. Use `$HOME/.claude/` or project-relative paths, not machine-specific absolute paths.
8. When updating site blog registries, update ALL registry files (primary `pages/blog/registry.php` AND secondary `pages/blog/posts/registry.php`). prior incident: secondary was missed → 404 on blog post.
9. **`/dr-archive` Step 0.1 nested git scan** — clean-git check MUST cover ALL nested repos under workspace, not only the workspace root. Use:
   ```sh
   find . -maxdepth 6 -name .git -type d -exec dirname {} \;
   ```
   For each — `git status --porcelain` + `git rev-list --count @{u}..HEAD`. Flag dirty trees and unpushed commits per Step 0.1 three-options gate. Source: prior incident — Email Agent sub-repo had 7 uncommitted file deltas + 1 unpushed commit, invisible until explicit nested scan.
