---
name: tech-stack
description: Tech stack selection by project type (static, API, full-stack, etc.). Use when creating a new project, service, or module or when choosing technologies.
---

# Tech Stack Selection

> **TL;DR:** When creating a new project, service, or module — select the tech stack STRICTLY based on project type. No guessing, no inventing, no asking. Apply these rules automatically.

## Core Principles

1. Prefer simplicity over complexity.
2. Prefer performance over convenience.
3. Prefer widely adopted tools with strong communities.
4. Do NOT introduce frameworks unless explicitly required.
5. Do NOT over-engineer.
6. Always select the stack based on project type.
7. Always use the latest stable (LTS where applicable) versions of ALL dependencies. If a latest major has breaking changes — adapt the code, do NOT downgrade.
8. Always include linting, formatting, and testing.
9. Always use Docker for backend services.

## Stack Selection Decision Tree

```mermaid
graph TD
    Start["NEW PROJECT /<br>SERVICE / MODULE"] --> TypeCheck{"Determine<br>Project Type"}

    TypeCheck -->|"Static"| StaticQ{"Multiple Pages?"}
    StaticQ -->|"No"| Landing["STATIC LANDING PAGE"]
    StaticQ -->|"Yes"| MultiPage["STATIC MULTI-PAGE"]

    TypeCheck -->|"Web Frontend"| WebQ{"SEO Required?"}
    WebQ -->|"Yes"| WebSEO["WEB FRONTEND (SEO)"]
    WebQ -->|"No"| SPA["SPA / DASHBOARD"]

    TypeCheck -->|"API"| APILang{"Language?"}
    APILang -->|"Node.js"| NodeAPI{"Microservice?"}
    NodeAPI -->|"Yes"| Micro["MICROSERVICE API"]
    NodeAPI -->|"No"| HighLoad["HIGH-LOAD API"]
    APILang -->|"Python"| PyAPI["PYTHON API"]

    TypeCheck -->|"AI/ML"| AIQ{"Type?"}
    AIQ -->|"API"| AIAPI["AI/LLM API"]
    AIQ -->|"Pipeline"| AIPipe["AI PIPELINES/RAG"]

    TypeCheck -->|"Real-time"| RTQ{"Type?"}
    RTQ -->|"Chat"| RTChat["REAL-TIME CHAT"]
    RTQ -->|"Media"| RTMedia["AUDIO/VIDEO"]
    RTQ -->|"WS"| RTWS["WEBSOCKETS"]

    TypeCheck -->|"Background"| BGJob["BACKGROUND JOBS"]
    TypeCheck -->|"Event-Driven"| EventDriven["EVENT-DRIVEN"]
    TypeCheck -->|"Media"| MediaQ{"Type?"}
    MediaQ -->|"Processing"| FileMedia["FILE PROCESSING"]
    MediaQ -->|"Streaming"| StreamMedia["STREAMING"]
    TypeCheck -->|"Monorepo"| Monorepo["MONOREPO"]
    TypeCheck -->|"Auth"| Auth["AUTH SERVICE"]
    TypeCheck -->|"Gateway"| Gateway["API GATEWAY"]
    TypeCheck -->|"MVP"| MVP["PROTOTYPING"]
    TypeCheck -->|"Search"| Search["SEARCH/RAG API"]
```

## Project Type -> Required Stack

### Frontend Projects

| Type | Stack |
|------|-------|
| **Static Landing** | HTML, CSS, Tailwind CSS, Alpine.js (opt). NO SPA. Docker optional. |
| **Static Multi-Page** | PHP, HTML, Tailwind CSS. SSR templates. NO SPA. Docker required. |
| **Web Frontend (SEO)** | Next.js, React, Tailwind, shadcn/ui, Vite, pnpm, Vitest, Playwright. Docker. |
| **SPA / Dashboard** | Vite, React or Vue, Tailwind, TanStack Query, Vitest. Docker. |

### Backend API Projects

| Type | Stack |
|------|-------|
| **Microservice API** | Nest.js, Fastify (MANDATORY), PostgreSQL, Prisma, Redis, NATS, Docker Compose. |
| **High-Load HTTP API** | Node.js, Fastify, PostgreSQL, Redis, k6. Docker. |
| **Python API (Modern)** | Python, FastAPI, uvicorn, uv, ruff, pydantic, sqlalchemy, alembic, pytest. Docker. |
| **API Gateway / BFF** | Node.js, Fastify, Zod, OpenAPI. Docker. |

### AI / ML Projects

| Type | Stack |
|------|-------|
| **AI / LLM API** | Python, FastAPI, uv, ruff, OpenAI/OpenRouter SDK, Redis. Docker. |
| **AI Pipelines / RAG** | Python, FastAPI, uv, ruff, LangChain/LlamaIndex, pgvector/Qdrant, Redis. Docker Compose. |
| **Search / Semantic** | Python, FastAPI, uv, ruff, pgvector/Qdrant/Weaviate. Docker Compose. |

### Real-time Projects

| Type | Stack |
|------|-------|
| **Real-Time Chat** | Node.js, Socket.IO or ws, Redis. Docker Compose. |
| **Audio / Video** | Node.js, WebRTC, mediasoup/LiveKit, Redis. Docker Compose. |
| **WebSockets-Only** | Node.js, ws or uWebSockets.js, Redis Pub/Sub. Docker. |

### Background / Event Projects

| Type | Stack |
|------|-------|
| **Background Jobs** | Python, FastAPI, Celery/Dramatiq, Redis/Kafka. Docker Compose. |
| **Python Workers** | Python, Celery/Dramatiq, Redis/RabbitMQ, uv, ruff. Docker Compose. |
| **Event-Driven** | Nest.js or FastAPI, NATS/Kafka, OpenTelemetry. Docker Compose. |

### Media Projects

| Type | Stack |
|------|-------|
| **File / Media Processing** | Python, FFmpeg, Celery, S3-compatible storage. Docker Compose. |
| **Streaming Platform** | Node.js, WebRTC, mediasoup, FFmpeg, CDN. Docker Compose. |

### Platform Projects

| Type | Stack |
|------|-------|
| **Monorepo** | Nx, TypeScript, pnpm, shared libraries, CI/CD. Docker. |
| **Auth / Identity** | Nest.js, Passport, JWT, OAuth2, Redis. Docker. |
| **Prototyping / MVP** | Next.js, API Routes, PostgreSQL, Prisma. Docker Compose. |

### Infrastructure / Backup

| Type | Stack |
|------|-------|
| **Server backups** | `restic` + Backblaze B2 (native backend, client-side encryption, dedup, snapshots). Config via `/etc/restic/`, systemd timer for daily backups, `backup-healthcheck.sh` for monitoring. First backup + restore test is mandatory. Use binary-installed restic (apt version lacks `self-update`). |
| **Database backups** | Per-engine tooling (`pg_dump`, `mysqldump`, `mongodump`) piped into restic — captures logical dump as a named file in the repo. |

Source: INFRA-0008 reflection — restic + B2 proven across arcana-www/prod/db; standardize to avoid revisiting the choice per-server.

## Mandatory Toolchains

### Python (ALWAYS)

```mermaid
graph LR
    Py["Python"] --> UV["uv"]
    Py --> Ruff["ruff"]
    Py --> Pytest["pytest"]
    Py --> Mypy["mypy (opt)"]
    Py --> Hooks["pre-commit"]
```

- `uv` — dependency & env management
- `ruff` — lint + format (replaces flake8, isort, black)
- `pytest` — testing
- `mypy` — typing (if used)
- `pre-commit hooks`

**FORBIDDEN:** `pip` without `uv`, `flake8`/`isort`/`black` when `ruff` present

### Node / TypeScript (ALWAYS)

```mermaid
graph LR
    Node["Node/TS"] --> PNPM["pnpm"]
    Node --> TS["TypeScript"]
    Node --> ESLint["eslint"]
    Node --> Prettier["prettier"]
    Node --> Vitest["vitest"]
    Node --> PW["playwright"]
    Node --> Build["tsup/swc"]
    Node --> Hooks["lefthook/husky"]
```

- `pnpm` — package manager
- `TypeScript` — mandatory
- `eslint` + `prettier` — lint + format
- `vitest` — testing
- `playwright` — E2E (frontend)
- `tsup`/`swc` — build
- `lefthook`/`husky` — git hooks

## Scaffold Checklist

After creating a new project in `Projects/*/code/`:
1. `git init` — initialize standalone repo (parent arcanada gitignores `Projects/*/code/`)
2. `pnpm outdated` / `uv pip list --outdated` — zero outdated = pass
3. Verify `.gitignore` covers `node_modules/`, `dist/`, `.env`
4. Initial commit with scaffold

Source: CONN-0002 — Model Connector code had no `.git` for weeks; discovered only at archive time.

## Docker Rules

1. Backend service -> Docker REQUIRED
2. Multiple services -> Docker Compose REQUIRED
3. Local env mirrors production
4. No `latest` tags
5. One container = one responsibility

## Dependency Version Policy

- **General rule:** ALWAYS install the **latest stable** (LTS where applicable) version of every dependency — runtime, toolchain, ORM, framework, CLI tool. If `pnpm add foo` installs a major version with breaking changes, **adapt the code to the new API** instead of downgrading. Downgrading to a previous major is only acceptable if the latest version has a critical, documented, unresolved bug.
- **Node.js:** LTS (even versions), `engines` field, `pnpm-lock.yaml`
- **Python:** latest stable minor, `pyproject.toml`, `uv.lock`
- **Audit after scaffold:** Run `pnpm outdated` (or `uv pip list --outdated`) immediately after project init. Zero outdated packages = pass.
- **AI hallucination guard:** Do NOT rely on training data for current package versions. Before specifying a version in `package.json` / `pyproject.toml`, verify the latest major via `npm view <pkg> version` (or `pip index versions <pkg>`). CONN-0001 incident: AI proposed Prisma 6 when Prisma 7 was already the latest stable — caught only at audit, cost rework.
- **Post-install verification (MANDATORY):** After every `pnpm add` / `uv add` during implementation, run `pnpm outdated` (or equivalent). If any dependency shows a newer major, update immediately — do not defer.

## Testing Policy

- Unit tests: **mandatory**
- Integration tests: if DB/queues exist
- E2E tests: for frontend and APIs
- CI fails on missing/failing tests

## Architecture Rules

1. No SPA where HTML suffices
2. Fastify > Express (always)
3. Redis = default cache
4. Queues != WebSockets
5. WebRTC = media only
6. Event-driven -> NATS or Kafka
7. Monorepo -> Nx
8. PHP = SSR/template reuse only
9. No exotic libraries without justification

## Forbidden

- SPA for landing pages
- Missing Docker for backend
- Missing linters
- Floating dependency versions
- Missing lock files
- Mixed service responsibilities
- Express when Fastify should be used

## When to Apply

This skill is loaded when:
- Creating a new project or service (PRD, VAN modes)
- Selecting tech stack during planning (PLAN mode)
- Keywords: "stack", "technology", "framework", "new project", "scaffold", "create project"

## Final Rule

If requirement is not explicitly stated by user:
- Choose **simplest valid stack** from this document
- Do NOT invent new stacks
- Do NOT ask which stack to use
- Apply rules **automatically**

## Reusable Templates

- `templates/nestjs-service-scaffold.md` — Phase-1 scaffold checklist for any new NestJS backend service in the Arcanada/Aether ecosystem. Covers init, config, Prisma wiring, health check, structured logging, error filter, validation pipe, and Docker integration. Use during `/dr-plan` Step 6 when the chosen stack is NestJS.
