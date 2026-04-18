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

When archiving a task, map the prefix to the destination subdirectory:

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
| `CONN` | `connectors/` |
| `SRCH` | `search/` |
| `LTM` | `research/` |
| *(unknown)* | `general/` |

Archive path:

```text
documentation/archive/{area}/archive-{task_id}.md
```

## Project Setup

When `/dr-init` initializes a project:

1. Create `datarim/` at the project root.
2. Create `documentation/archive/` for long-term archives.
3. Add `datarim/` to `.gitignore`.
4. Keep `documentation/` committed.

This allows parallel local workflow state with committed shared archives.

## Critical Rules

1. `datarim/` is workflow truth; `documentation/archive/` is archive truth.
2. Every report filename includes the task ID.
3. `documentation/tasks/` must not exist.
4. `activeContext.md` must stay current.
5. Backlog uses the active + archive split.
6. Path resolution happens before any write.
7. Use `$HOME/.claude/` or project-relative paths, not machine-specific absolute paths.
8. When updating site blog registries, update ALL registry files (primary `pages/blog/registry.php` AND secondary `pages/blog/posts/registry.php`). TUNE-0019: secondary was missed → 404 on blog post.
