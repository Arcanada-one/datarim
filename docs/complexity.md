# Complexity Levels

Datarim uses a 4-level complexity system to determine which pipeline stages to run.

## Decision Tree

| Level | Files | LOC | Architecture | Example |
|-------|-------|-----|-------------|---------|
| **L1** Quick Fix | 1 | <50 | None | Fix typo in README, fix a citation in a legal brief, correct a date in a report |
| **L2** Enhancement | 2-5 | <200 | Minor refactor | Add input validation, add a section to a research paper, create a project status update |
| **L3** Feature | 5-15 | 200-1000 | Design needed | Implement OAuth2, write a grant proposal, create compliance documentation, design a landing page |
| **L4** Major Feature | 15+ | >1000 | Complex | Migrate to microservices, write a technical book, complete a regulatory filing, build an observability stack |

## Pipeline Routes

```
L1: init → do → reflect → archive
L2: init → [prd] → plan → do → [qa] → reflect → archive
L3: init → prd → plan → design → do → qa → [compliance] → reflect → archive
L4: init → prd → plan → design → phased-do → qa → compliance → reflect → archive
```

Brackets `[]` = optional at that level.

## How Complexity is Assessed

The `/dr-init` command determines complexity by analyzing:

1. **Scope:** How many files will be touched?
2. **Lines of code:** Rough estimate of changes
3. **Architecture impact:** Does the task change system structure?
4. **Dependencies:** Does it affect other systems or services?
5. **Risk:** Is it reversible? What's the blast radius?

## When to Override

The agent's complexity assessment is a suggestion. The user can override:

```
/dr-init Add caching layer
# Agent suggests L2, but you know it's more complex:
"This is L3 — it touches the data layer, cache invalidation, and monitoring."
```

## L4: Phased Implementation

For L4 tasks, `/dr-do` splits into multiple phases:
1. Each phase is a self-contained unit of work
2. Each phase can be independently tested
3. Progress is tracked per-phase in `datarim/progress.md`
4. If a phase fails, earlier phases are still valid
