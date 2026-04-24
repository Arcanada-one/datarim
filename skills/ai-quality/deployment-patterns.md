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

INFRA-0020 installed torch + sentence-transformers + 30 deps into system Python on arcana-db. Future `pip install` for another service may upgrade a shared dependency and break the embedding API silently. The same pattern occurred in LTM-0002 (Docker was the correct isolation) and EMAIL-0001 (system pip, no isolation).

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

SRCH-0002: FlagEmbedding 1.3.5 failed at startup with transformers 5.x (`is_torch_fx_available` removed). Pinning to `<5.0` fixed it. A 5-second import check would have caught this before the service restart.

### Verify Model Architecture Impact

When switching model loaders (e.g. `SentenceTransformer` → `BGEM3FlagModel`), do not assume single-variable predictions (like "fp16 = 50% less RAM") apply. A different loader loads a different architecture.

SRCH-0002: plan predicted fp16 would reduce RAM from 914MB to ~450MB. Actual: 2,400MB (+163%) because `BGEM3FlagModel` loads sparse_linear + colbert_linear components on top of the base model. Latency also increased 3x (118ms → 360ms) due to heavier inference path. The prediction was based on fp16 alone, ignoring the architectural change.

**Rule:** When changing model loaders, benchmark RAM and latency empirically before committing to production. Do not extrapolate from documentation of a single feature (fp16).

---

## NestJS @Global() in Multi-Bootstrap Monorepos

`@Global()` on a module only applies within the bootstrap context where its root module is registered. In a NestJS monorepo with separate `main.ts` files (e.g. API, Worker, Bot), each bootstrap creates an independent DI container. A `@Global()` module registered in `AppModule` is NOT available in `WorkerModule`'s container.

**Rule:** In multi-bootstrap monorepos, explicitly import shared modules (RedisModule, PrismaModule, etc.) in every app module that needs them, regardless of `@Global()`.

TRANS-0013: Worker crashed with `RedisService not found` because `RedisModule` was `@Global()` but only bootstrapped via `AppModule`. Worker had its own bootstrap and needed an explicit import.

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

CONN-0004 found 5 of 6 production bugs only during Docker deployment — none surfaced in unit tests. Issues: Prisma config missing from image, circular DI crash, Alpine/glibc incompatibility, root user restrictions, validation pipe scope. A 30-second Docker smoke test catches the entire class.

### When to apply

Every `/dr-qa` for projects with Docker deployment. Unit tests pass ≠ container works.

---

## CLI Connector Docker Pattern

When deploying services that spawn CLI tools as subprocesses (Claude Code, Cursor, Codex, Gemini CLI):

1. **Use `node:22-slim`** (Debian), NOT `alpine` — native CLI binaries require glibc
2. **Create non-root user** — Claude CLI (and likely others) refuse elevated permission modes as root
3. **Persistent volume for auth** — CLI subscription auth stores tokens in `~/.claude/.credentials.json`; Docker volume preserves across restarts

```dockerfile
FROM node:22-slim AS production
RUN npm install -g @anthropic-ai/claude-code
RUN useradd -m -s /bin/bash connector
USER connector
```

```yaml
volumes:
  - cli-auth:/home/connector/.claude
```

CONN-0004: Three bugs from wrong base image (Alpine musl) + root user + ephemeral auth. Pattern applies to all CLI connector deployments.

### CLI Installer in Docker (non-root user)

When a CLI tool installs via `curl | bash` to `$HOME` (e.g. Cursor CLI):

1. **Install as root** during Docker build (default user)
2. **Copy to shared path**: `cp -r /root/.local/share/<tool> /opt/<tool>`
3. **Fix permissions**: `chmod -R a+rX /opt/<tool>`
4. **Symlink binary**: `ln -sf /opt/<tool>/.../<binary> /usr/local/bin/<binary>`
5. **Pre-create user dirs**: `mkdir -p /home/<user>/.<tool> && chown <user>:<user> /home/<user>/.<tool>`

Do NOT symlink to `/root/...` — non-root user cannot read `/root/`. Do NOT rely on Docker volume creating dirs with correct ownership — volumes mount as root.

CONN-0008: 4 Dockerfile iterations because `curl | bash` installed to `/root/.local/share/cursor-agent/`, inaccessible to non-root `connector` user. Same root→non-root pattern as CONN-0004.

### CLI Output Channel Conventions

Each CLI agent has its own output channel convention — do NOT assume uniformity:

| CLI | Success JSON | Error JSON | Exit code on error |
|-----|-------------|------------|-------------------|
| Claude Code | stdout | stdout (`is_error: true`) | 0 |
| Cursor | stdout | stdout (`is_error: true`) | 0 |
| Gemini CLI | stdout | **stderr** (last JSON block) | 1 |

CONN-0007: Gemini CLI outputs error JSON to stderr, not stdout. Parser must try stdout first, then extract last JSON block from stderr if stdout is empty. stderr always contains IDE companion noise (`[IDEClient]`) — filter before error classification.

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

CONN-0007: Gemini CLI scans workspace on startup. Spawning from `/tmp/gemini_*` prevents token waste. Same pattern used in Email Agent (`email_agent.py:196`).

## Async HTTP Client — Singleton Pattern

### Rule

In async Python (FastAPI/uvicorn), **always use a singleton `httpx.AsyncClient`** with lifespan management. Never create a new client per request or per function call.

### Why

SRCH-0020: Scrutator `embedder.py` created a new `httpx.AsyncClient` per call to `embed_texts()` and `embed_sparse()`. Each `index_document()` = 2 clients. After 2-3 requests (4-6 clients), TCP sockets exhausted → 503 with empty error message. Restarting the service temporarily fixed it (socket cleanup).

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
# BAD
except Exception:
    pass

# GOOD
except Exception:
    logger.warning("Operation X failed for %s", context, exc_info=True)
```

### Why

SRCH-0020: Sparse indexing failures in `indexer.py` were invisible for weeks due to `except: pass`. The embedding API was intermittently failing, but no evidence existed in logs. A single `logger.warning()` would have surfaced the root cause immediately.