# Project Documentation Stubs

> This is a meta-template used by `/dr-init` project scaffolding (skill: `project-init.md`).
> Each section below is a separate file to be created under `docs/` per the **Diátaxis Documentation Taxonomy Mandate** (`skills/diataxis-docs.md`).
> The agent reads this template and creates individual files from each section. Category READMEs (`docs/{tutorials,how-to,reference,explanation}/README.md`) come from `templates/docs-diataxis/<category>/README.md` (separate stubs, not duplicated here).
>
> **Mapping (per skill § Mapping Table):** architecture → reference (system map); testing / deployment / gotchas → how-to (problem-solving recipes).

---

## File: docs/reference/architecture.md

```markdown
# Architecture

> Last updated: __DATE__

## Overview

[TODO: High-level description of the system architecture]

## Components

| Component | Path | Language | Purpose |
|-----------|------|----------|---------|
| [TODO] | `src/` | [TODO] | [TODO] |

## Data Flow

[TODO: Describe how data flows through the system]

## Security Model

[TODO: Authentication, authorization, data protection]
```

---

## File: docs/how-to/testing.md

```markdown
# Testing

> Last updated: __DATE__

## Strategy

[TODO: Which test types are used and why]

## Test Structure

| Type | Location | Runner | Purpose |
|------|----------|--------|---------|
| Unit | `test/` | [TODO] | Core logic |
| Integration | `test/` | [TODO] | Component interaction |
| E2E | `test/e2e/` | [TODO] | Full user flows |

## How to Run

[TODO: Commands for running tests]

## Coverage Expectations

[TODO: Minimum coverage thresholds and what to prioritize]
```

---

## File: docs/how-to/deployment.md

```markdown
# Deployment

> Last updated: __DATE__

## Environments

| Environment | URL | Purpose |
|-------------|-----|---------|
| Local | `localhost:PORT` | Development |
| Production | [TODO] | Live |

## Deploy Steps

[TODO: Step-by-step deployment instructions]

## Rollback

[TODO: How to roll back a bad deployment]

## Monitoring

[TODO: Health checks, alerts, dashboards]
```

---

## File: docs/how-to/gotchas.md

```markdown
# Gotchas

> Hard-won lessons organized by category. Add entries as they are discovered.
> Each entry: **what happened** — **what to do / avoid**.

## Setup

[Nothing yet — add entries as discoveries are made]

## Development

[Nothing yet]

## Deployment

[Nothing yet]

## Dependencies

[Nothing yet]
```
