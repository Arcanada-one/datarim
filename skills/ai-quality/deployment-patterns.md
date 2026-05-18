---
name: ai-quality/deployment-patterns
description: Deployment patterns — dependency isolation, Docker smoke tests, NestJS DI, CLI connector Docker setup. Load when deploying services or debugging container issues.
---

# Deployment Patterns

## Dependency Isolation

When deploying services on shared servers, **isolate dependencies** from the system Python/Node.

### Rule

Use **venv** (Python) or **Docker** for any service that:
1. Installs ML libraries (torch, transformers, sentence-transformers) — they pull 30+ transitive deps
2. Runs as a systemd service (long-lived process)
3. Shares the server with other services

`pip install --break-system-packages` is acceptable for one-off scripts, NOT for production services.

### Why

A real incident installed torch + sentence-transformers + 30 deps into system Python on a shared host. Future `pip install` for another service may upgrade a shared dependency and break the embedding API silently. The same pattern recurred on two further services — Docker was the correct isolation in one, system pip with no isolation in the other.

### Quick Setup

```bash
python3 -m venv /opt/my-service/.venv
source /opt/my-service/.venv/bin/activate
pip install -r requirements.txt
```

In systemd: `ExecStart=/opt/my-service/.venv/bin/python3 main.py`

### Pin ML Dependencies

ML ecosystem has frequent breaking changes across major versions. When installing ML libraries:

1. **Pin major versions** — `transformers>=4.45,<5.0`, not `transformers>=4.45`
2. **Pre-deploy import check** — before restarting a service, verify the import works:
   ```bash
   /opt/my-service/.venv/bin/python3 -c "from FlagEmbedding import BGEM3FlagModel; print('OK')"
   ```
3. **Capture `pip freeze`** after a working install for reproducibility

Real incident: FlagEmbedding 1.3.5 failed at startup with transformers 5.x (`is_torch_fx_available` removed). Pinning to `<5.0` fixed it. A 5-second import check would have caught this before the service restart.

### Verify Model Architecture Impact

When switching model loaders (e.g. `SentenceTransformer` → `BGEM3FlagModel`), do not assume single-variable predictions (like "fp16 = 50% less RAM") apply. A different loader loads a different architecture.

Real incident: a plan predicted fp16 would reduce RAM from 914MB to ~450MB. Actual: 2,400MB (+163%) because `BGEM3FlagModel` loads sparse_linear + colbert_linear components on top of the base model. Latency also increased 3x (118ms → 360ms) due to heavier inference path. The prediction was based on fp16 alone, ignoring the architectural change.

**Rule:** When changing model loaders, benchmark RAM and latency empirically before committing to production. Do not extrapolate from documentation of a single feature (fp16).

---

## NODE_ENV in Container Environments — Anti-Pattern

`NODE_ENV=development` в Docker container'е (compose, Dockerfile `ENV`, docker run `-e`) — это анти-pattern. Контейнер не знает дев-режима.

### Rule

**Container default = `NODE_ENV=production`.** Dev-mode-only зависимости (pino-pretty, ts-node, source-map-support, error-stack-with-context, etc.) живут в `devDependencies`. Production Dockerfile делает `npm ci --omit=dev` → эти пакеты физически отсутствуют в image. Любой код, который их `require()` при `NODE_ENV=development`, упадёт с `Cannot find module ...` на старте.

### Why

Real incident: Dockerfile корректно делал `npm ci --omit=dev`, но `docker-compose.yml` выставлял `NODE_ENV=development`. Pino logger conditionally подключал `pino-pretty` транспорт при dev-режиме. Контейнер crashed at startup (`unable to determine transport target for "pino-pretty"`). 5 минут диагностики + 1 цикл compose rebuild.

### Pattern

```yaml
# docker-compose.yml — production-mode default for any container
services:
  app:
    environment:
      NODE_ENV: production    # <-- not development
      LOG_LEVEL: info
      # actual dev/staging differentiation: separate compose file or env override
```

```typescript
// pino setup — pretty transport ONLY when explicitly requested
transport: process.env.LOG_PRETTY === '1'
  ? { target: 'pino-pretty', options: { colorize: true } }
  : undefined
```

Локальный dev (host machine, `npm run start:dev`) сохраняет `NODE_ENV=development` через npm scripts — там devDeps присутствуют. Container никогда.

### When to apply

- Любой Dockerfile + docker-compose.yml для Node.js / Python / Ruby сервиса.
- Общий принцип: «container env mirrors prod», даже если container запущен на dev-машине.

---

## NestJS @Global() in Multi-Bootstrap Monorepos

`@Global()` on a module only applies within the bootstrap context where its root module is registered. In a NestJS monorepo with separate `main.ts` files (e.g. API, Worker, Bot), each bootstrap creates an independent DI container. A `@Global()` module registered in `AppModule` is NOT available in `WorkerModule`'s container.

**Rule:** In multi-bootstrap monorepos, explicitly import shared modules (RedisModule, PrismaModule, etc.) in every app module that needs them, regardless of `@Global()`.

Real incident: Worker crashed with `RedisService not found` because `RedisModule` was `@Global()` but only bootstrapped via `AppModule`. Worker had its own bootstrap and needed an explicit import.

---

## Docker Smoke Test

Before declaring implementation complete on any Docker-deployed service, run a minimal smoke test:

```bash
docker compose up -d --build
# Wait for health
curl -sf http://localhost:PORT/health || exit 1
# Basic API call
curl -sf -X POST http://localhost:PORT/endpoint -H 'Content-Type: application/json' -d '...'
docker compose down
```

### Why

A real Docker deployment incident found 5 of 6 production bugs only during Docker deployment — none surfaced in unit tests. Issues: Prisma config missing from image, circular DI crash, Alpine/glibc incompatibility, root user restrictions, validation pipe scope. A 30-second Docker smoke test catches the entire class.

### When to apply

Every `/dr-qa` for projects with Docker deployment. Unit tests pass ≠ container works.

---

## CLI Connector Docker Pattern

When deploying services that spawn CLI tools as subprocesses (Claude Code, Cursor, Codex, Gemini CLI):

1. **Use `node:22-slim`** (Debian), NOT `alpine` — native CLI binaries require glibc
2. **Create non-root user** — Claude CLI (and likely others) refuse elevated permission modes as root
3. **Persistent volume for auth** — CLI subscription auth stores tokens in `~/.claude/.credentials.json`; Docker volume preserves across restarts
4. **Pin and verify the installer** (Datarim § Security Mandate S4) — never pipe a remote installer straight into a shell. Download the artifact, verify its SHA-256 against the upstream-published hash, then execute.

Reference shape (renew the version + hash in lockstep via Renovate / Dependabot):

```dockerfile
FROM node:22-slim AS production

ARG CLAUDE_CLI_VERSION=0.42.4
ARG CLAUDE_CLI_SHA256=<sha256-from-upstream-release>
RUN set -eu \
 && curl -fsSL -o /tmp/claude-cli.tgz \
      "https://example.com/claude-cli/${CLAUDE_CLI_VERSION}/claude-cli-linux-x64.tgz" \
 && echo "${CLAUDE_CLI_SHA256}  /tmp/claude-cli.tgz" | sha256sum --check \
 && tar -xzf /tmp/claude-cli.tgz -C /opt \
 && ln -sf /opt/claude-cli/bin/claude /usr/local/bin/claude \
 && rm /tmp/claude-cli.tgz

RUN useradd -m -s /bin/bash connector
USER connector
```

```yaml
volumes:
  - cli-auth:/home/connector/.claude
```

`npm`-distributed CLIs install via the lockfile and signature verification:

```dockerfile
COPY package.json package-lock.json ./
RUN npm ci && npm audit signatures
```

<!-- security:counter-example -->
# UNSAFE — no integrity check, the installer can be swapped server-side
# at any moment and every consumer pulls the swap silently.
RUN curl -fsSL https://claude.ai/install.sh | bash
<!-- /security:counter-example -->

Real incident: Three bugs from wrong base image (Alpine musl) + root user + ephemeral auth. Pattern applies to all CLI connector deployments.

### CLI Installer in Docker (non-root user)

When a CLI tool ships only a shell installer that writes into `$HOME` (e.g. Cursor CLI), wrap it in a hash-pinned download as above. Then move the resulting tree into a shared path the non-root user can read:

1. **Install as root** during Docker build (default user); pin and verify the tarball before extraction.
2. **Copy to shared path**: `cp -r /root/.local/share/<tool> /opt/<tool>`
3. **Fix permissions**: `chmod -R a+rX /opt/<tool>`
4. **Symlink binary**: `ln -sf /opt/<tool>/.../<binary> /usr/local/bin/<binary>`
5. **Pre-create user dirs**: `mkdir -p /home/<user>/.<tool> && chown <user>:<user> /home/<user>/.<tool>`

Do NOT symlink to `/root/...` — non-root user cannot read `/root/`. Do NOT rely on Docker volume creating dirs with correct ownership — volumes mount as root.

Real incident: 4 Dockerfile iterations because the upstream installer wrote to `/root/.local/share/cursor-agent/`, inaccessible to non-root `connector` user. Same root→non-root pattern recurs across CLI deployments.

### CLI Output Channel Conventions

Each CLI agent has its own output channel convention — do NOT assume uniformity:

| CLI | Success JSON | Error JSON | Exit code on error |
|-----|-------------|------------|-------------------|
| Claude Code | stdout | stdout (`is_error: true`) | 0 |
| Cursor | stdout | stdout (`is_error: true`) | 0 |
| Gemini CLI | stdout | **stderr** (last JSON block) | 1 |

Real incident: Gemini CLI outputs error JSON to stderr, not stdout. Parser must try stdout first, then extract last JSON block from stderr if stdout is empty. stderr always contains IDE companion noise (`[IDEClient]`) — filter before error classification.

### CWD Isolation for CLI Connectors

Some CLI tools scan the working directory on startup for project context. If spawned from a directory with many files, this wastes tokens and adds latency.

**Pattern:** Create an isolated temp dir before spawning, clean up after:
```typescript
const cwd = await mkdtemp(join(tmpdir(), 'cli_'));
try {
  spawn(binary, args, { cwd });
} finally {
  rm(cwd, { recursive: true, force: true }).catch(() => {});
}
```

Real incident: Gemini CLI scans workspace on startup. Spawning from `/tmp/gemini_*` prevents token waste. Same pattern used in Email Agent (`email_agent.py:196`).

## Async HTTP Client — Singleton Pattern

### Rule

In async Python (FastAPI/uvicorn), **always use a singleton `httpx.AsyncClient`** with lifespan management. Never create a new client per request or per function call.

### Why

Real incident: Scrutator `embedder.py` created a new `httpx.AsyncClient` per call to `embed_texts()` and `embed_sparse()`. Each `index_document()` = 2 clients. After 2-3 requests (4-6 clients), TCP sockets exhausted → 503 with empty error message. Restarting the service temporarily fixed it (socket cleanup).

### Pattern

```python
_client: httpx.AsyncClient | None = None

async def get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=10.0),
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=5),
        )
    return _client

async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
```

Register `close_client()` in FastAPI lifespan `yield` block.

## Silent Exception Handling — Anti-Pattern

### Rule

Never use `except Exception: pass` in production code. Always log with `exc_info=True`:

```python
# nosec-extract -- pedagogical except-fragment, intentionally non-parsable
# BAD
except Exception:
    pass

# GOOD
except Exception:
    logger.warning("Operation X failed for %s", context, exc_info=True)
```

### Why

Real incident: Sparse indexing failures in `indexer.py` were invisible for weeks due to `except: pass`. The embedding API was intermittently failing, but no evidence existed in logs. A single `logger.warning()` would have surfaced the root cause immediately.

## Failure-Path Drills — Two-Axis Rollback Contract Verification

Rollback contracts have **two orthogonal failure axes**. A drill that exercises only one axis leaves the other unverified, and the gap surfaces the next time production hits the missed axis — usually at an unscheduled moment.

### The two axes

1. **Image axis** — the bug lives inside the application image (code, binary, baked-in config). The build still produces an image; the container starts but exits, crashes, or never reaches healthy due to runtime behavior.
2. **Config axis** — the bug lives in deploy-time configuration external to the image (compose file, env file, healthcheck path, port mapping, volume bind, deploy script). The image is unchanged; the container starts but is misconfigured by the surrounding deploy contract.

Image-tag rollback (`tag :previous → :latest`) restores the IMAGE only. **If the failure root cause is on the config axis, rolling back the image has no effect** — the `:previous` container runs with the SAME broken config from disk and reproduces the failure. The rollback path itself fails and the cascade stays open.

### Drill recipe (per service, per release cycle)

Test BOTH axes in pairs (or alternate them on consecutive drill cycles). Each axis exercises a different layer of the rollback contract.

- **Code-break drill (image axis):** introduce a bug into application source — e.g. an unconditional throw in the bootstrap function, a syntax error caught at runtime, an obviously bad return type. The build still succeeds; the container starts but exits or stays unhealthy. Rollback to `:previous` should restore service ≤ the recovery budget.
- **Config-break drill (config axis):** introduce a bug into deploy-time config — e.g. a healthcheck endpoint that does not exist on the running service, a missing required env variable, a port that does not match the listener. The image is unchanged; the container starts but the deploy contract marks it unhealthy. Rollback MUST restore both image AND config to the last-known-good state.

A rollback contract that handles only the image axis silently fails on every config-axis incident — and config breaks are common (renames, env regression, healthcheck drift, volume permission). Without both-axis coverage in drills, the gap is invisible until production hits it.

### Per drill: capture and document

- Timeline (UTC) — push, build complete, deploy start, failure detection, rollback engagement, recovery (or rollback-failed), Ops Bot signal sent + delivery code.
- AC disposition — split the rollback budget into **engagement** (≤Xs from failure detection) and **recovery** (≤Ys to fully functional). The two are different metrics and a contract may pass one and fail the other.
- Critical-path notification delivery — receiver returned 2xx, payload was parseable, on-call channel was reachable.
- Cascade containment — dependent services (workers, bots, downstream consumers) recovered within budget or stayed contained without ripple.

### When to apply

Any service with a CI/CD rollback contract. Image-axis-only rollback designs SHOULD be flagged in code review as incomplete; the question to ask is: «if the breakage lives in the deploy config rather than the image, what does this rollback do?»

### Source

Two consecutive drills on the same service, same release cycle, same rollback contract:

- **Code-break drill (image axis)** — exposed an `if`-guard bypass on the failure-detection step (verify outcome `skipped` ≠ `failure` → rollback never engaged). Detection-layer fix landed.
- **Config-break drill (config axis)** — exposed that the rollback step swaps the image tag but does NOT restore the deploy config from the previous-known-good commit. With a config-only break, the `:previous` image runs against the SAME broken config and the rollback step itself fails. Detection layer worked; execution layer was incomplete.

Both drills caught real production hardening gaps in controlled outage windows. Each window cost ~10–12 min; an unscheduled production accident at the same blast radius costs unbounded MTTR.

## Critical-Path Secret Presence Gate

Any CI workflow that fires alerts via `Authorization: Bearer ${{ secrets.X }}` (or any header that interpolates a secret into a critical-path notification) MUST include a pre-deploy lint step that fails when the secret is empty.

### Why

Empty secrets pass YAML interpolation silently. The `Authorization: Bearer ` header becomes literally `Bearer ` (trailing space, no token), and the receiver returns 401 / 403 / quietly drops the request. Alerting is silently broken until a drill or a real incident fires the path — by which point the alert is the thing that should have warned you.

The cost of the gate is ~3 lines of YAML per repo. The cost of silent alerting is unbounded — every incident during the silent window is invisible to on-call.

### Pattern

A dedicated lint job that the build/deploy job depends on:

```yaml
jobs:
  secret-presence-gate:
    runs-on: ubuntu-latest
    steps:
      - name: Verify critical alert secrets are present
        run: |
          [ -n "${{ secrets.OPSBOT_API_KEY }}" ] || \
            { echo "::error::OPSBOT_API_KEY is empty — alerting broken"; exit 1; }

  build:
    needs: secret-presence-gate
    runs-on: ubuntu-latest
    steps:
      - ...
```

For a workflow that wires multiple critical-path secrets, declare each one explicitly — do not collapse them into a single check. A single missing secret should produce a single named error so on-call can fix it without bisecting.

### When to apply

Any secret used in critical-path notifications: incident-bot API tokens, paging-system keys, Slack incident webhooks, container-registry tokens used by deploy steps, deploy SSH keys. The rule of thumb: «if this secret is empty and a real incident fires the path, does anyone get notified?» — if «no», this secret is critical-path and needs the presence gate.

### What this does NOT do

- It does not validate that the secret is **correct** — only that it is non-empty. A wrong-but-present token still fails at the receiver. Pair the presence gate with a periodic synthetic-fire test (drill-style) that POSTs a known payload and asserts 2xx, to catch wrong-token regressions.
- It does not catch secrets that are present in `vars.X` but missing from `secrets.X` (or vice versa). Apply the gate to whichever scope the workflow actually uses.

### Source

A drill on a service with a previously-validated rollback contract. The workflow correctly fired the fatal-notify path on rollback failure, but the request was rejected with `curl: (22) ... 401` because `Authorization: Bearer ` was empty — the GitHub Secret holding the token had been removed or never set on this repo. The alert never reached the receiver. Silent-alerting failure window: unknown duration before the drill caught it.