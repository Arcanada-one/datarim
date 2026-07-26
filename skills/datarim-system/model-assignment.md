# Datarim System — Model Assignment

## Model Assignment Convention

Each agent and task-skill should specify a `model` field in YAML frontmatter to optimize capability and cost without losing quality.

### Available Values

| Value | Behavior |
|-------|----------|
| `opus` | Most capable, highest cost |
| `sonnet` | Balanced default |
| `haiku` | Fast and low cost |
| `<full-id>` | Version-pinned model identifier |
| `inherit` | Use caller model |

### Decision Matrix

| Use **opus** when... | Use **sonnet** when... | Use **haiku** when... |
|----------------------|------------------------|------------------------|
| Architectural decisions | Standard code/content work | Simple lookups |
| Security analysis | Structured tasks | Test execution |
| Strategic evaluation | Editorial review | API calls |
| Multi-perspective debate | Knowledge maintenance | Mechanical output |
| Critical reasoning | Standard QA | Shell utilities |

### Reference vs Task Skills

- Reference skills omit `model` and inherit from the caller.
- Task skills declare `model` explicitly.

Reference skills: `datarim-system`, `ai-quality`, `security`, `testing`, `performance`, `tech-stack`

Task-skill examples: `dream`, `consilium`, `factcheck`, `humanize`

### Effort Field

Both agents and skills may specify `effort: low|medium|high|max`.

- Use `max` only for very complex one-off tasks.
- Otherwise inherit from the session unless a task-specific override is justified.

### Prefer vendor-default model and effort

CLI-agent runtimes default to the current vendor-default model and the
vendor-default reasoning effort. Do not pin an older model generation merely
to preserve prior behavior. When a vendor changes its defaults, Datarim follows
the new defaults; stale pins are bugs to remove.

In `config/model-tiers.yaml`, `selection: vendor-default` means the adapter
omits its model override. It is never a literal model ID. The surrounding tier
key records capability intent for audit and for an explicit task override; it
does not manufacture a tier-specific vendor model when the CLI exposes only
one default.

A task may deliberately use a version-pinned `<full-id>` when it explicitly
requires a specific model. Record a one-line reason beside that override.

Prefer the newest stable CLI-agent version. Where installation or upgrade is permitted
by the environment and operator policy, keep the CLI current. Where
software changes are restricted, emit one advisory recommendation that names
the detected version and suggests upgrading when a newer stable version is
known. Version detection and upgrade advice must not block a pipeline, change
routing, or alter an exit code. Never install or upgrade where policy forbids it.

This section governs CLI-agent executors and their model and effort defaults.
The latest-stable rule in `skills/tech-stack/SKILL.md` governs dependencies in
the user's project; it is a separate axis and is not duplicated here.

### Current Assignments

> Snapshot of explicit-model assignments. Refresh on changes via `/dr-optimize` or routine reflection. The lists below are alphabetical for diff-stability; canonical source remains the `model:` field in each artifact.

**Agents (17):**
- `opus`: architect, planner, reviewer, security, skill-creator, strategist
- `sonnet`: code-simplifier, compliance, developer, devops, editor, librarian, optimizer, researcher, sre, writer
- `haiku`: tester

**Task-skills (14, explicit `model`):**
- `opus`: consilium, evolution
- `sonnet`: compliance, discovery, dream, factcheck, frontend-ui, humanize, infra-automation, research-workflow, visual-maps, writing
- `haiku`: publishing, utilities

**Reference skills (no `model` field — inherit from caller):**
- ai-quality, cta-format, datarim-doctor, datarim-system, file-sync-config, performance, project-init, reflecting, release-verify, security, security-baseline, tech-stack, testing
