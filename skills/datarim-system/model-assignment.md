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

> Snapshot of the `model:` field as it stands on the surface, measured rather
> than maintained by hand. Canonical source remains the field in each artifact;
> re-measure with the commands below rather than editing the counts.

**Not one artifact names a concrete model.** Every `model:` field on the
instruction surface is `inherit`, which is what the vendor-default rule above
prescribes: the tier carries the capability intent (`metadata.model_tier`,
present on 19 artifacts) and the adapter stays silent about the model, so
whatever the operator's session is already talking to answers.

| Surface | Count | `model:` |
|---|---|---|
| Agents | 19 | `inherit` — all 19 |
| Skills | 20 | `inherit` |
| Skills | 53 | no `model:` field (inherit from the caller by absence) |

Skills carrying `model: inherit` explicitly: autonomous-mode, compliance,
consilium, context-window-self-clearing, discovery, dream, evolution, factcheck,
fleet, frontend-ui, humanize, image-prompting, immutability, infra-automation,
publishing, research-workflow, utilities, visual-maps, wizard, writing.

Re-measure:

```sh
for f in agents/*.md; do rg -m1 '^model:' "$f"; done | sort | uniq -c
for f in skills/*/SKILL.md; do rg -m1 '^model:' "$f"; done | sort | uniq -c
```

`check-skill-frontmatter.sh` accepts `inherit|sonnet|opus|haiku` or a full model
ID, so a concrete value here passes validation and is still refused by this
policy. What keeps the surface uniform is this rule, not the validator.
