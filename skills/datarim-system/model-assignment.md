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

### Current Assignments (v1.6.0)

**Agents (16):**
- `opus`: architect, planner, strategist, security, reviewer, skill-creator
- `sonnet`: developer, compliance, code-simplifier, devops, editor, librarian, optimizer, sre, writer
- `haiku`: tester

**Task-skills (14):**
- `opus`: consilium, evolution, incident-investigation
- `sonnet`: discovery, compliance, dream, factcheck, humanize, marketing, seo-launch, visual-maps, writing
- `haiku`: telegram-publishing, utilities

**Reference skills (6):**
- datarim-system, ai-quality, security, testing, performance, tech-stack
