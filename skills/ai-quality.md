---
name: ai-quality
description: Five pillars of AI-assisted development — decomposition, TDD, architecture-first, focused work, context. Method size limits, DoD, stubbing.
---

# AI Quality & Best Practices

> **TL;DR:** These 5 pillars guide AI-assisted development. Apply them consistently for 30-50% better code quality and 40-50% fewer bugs.

## THE 5 PILLARS OF QUALITY AI DEVELOPMENT

### 1. DECOMPOSITION (Rules #1, #3, #9)
> **Break complex tasks into small, focused units.**

```
KEY LIMITS:
|- Max 50 lines per method
|- Max 7-9 objects in working memory
|- One responsibility per function
```

**Why:** AI loses focus with complexity. Small units = better output.

---

### 2. TEST-FIRST (Rules #2, #5, #6)
> **Tests are hallucination filters. Mock edges, not logic.**

```
SEQUENCE:
1. Write tests BEFORE code
2. Define "done" explicitly (DoD)
3. Cover corner cases upfront
4. STRICT mocking: edges only, NO data fitting
```

**Why:** Tests catch AI mistakes. No tests = no safety net.

---

### 3. ARCHITECTURE-FIRST (Rules #7, #8)
> **Approve structure before coding.**

```
APPROACH:
1. Create skeleton with stubs
2. Review architecture
3. Implement one method at a time
```

**Why:** Bad architecture = wasted work. Validate first.

---

### 4. FOCUSED WORK (Rules #10, #11, #12)
> **Narrow context improves quality.**

```
PRACTICES:
|- Review one method at a time
|- Define clear boundaries (what we DON'T do)
|- Verify AI can solve before starting
|- Authorization prompts to user: 1 sentence risk + 1 yes/no question.
   Threat models → docs, not interactive prompt.
```

**Why:** Broad context = scattered results. Focus = precision.
Source (auth UX): LTM-0001 — user requested simpler prompts after a 7-option authorization table.

---

### 5. CONTEXT MANAGEMENT (Rules #4, #13, #14, #15)
> **Right information at right time.**

```
ELEMENTS:
|- Gather requirements BEFORE coding
|- Document transaction isolation needs
|- Structure datarim hierarchically
|- Engineer prompts carefully
```

**Why:** Bad context = bad output. Quality in = quality out.

---

## STAGE-RULE MAPPING

Load only the rules relevant to your current stage:

| Stage | Rules to Apply | Focus |
|-------|---------------|-------|
| **/dr-init** | #4 Requirements, #12 Complexity | Is the task well-defined? Can AI solve it? |
| **/dr-plan** | #1 Stubbing, #5 DoD, #6 Corner Cases, #7 Skeleton, #11 Boundaries | Decompose, define scope and done criteria |
| **/dr-design** | #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions | Design quality, keep it simple |
| **/dr-do** | #2 TDD, #3 Method Size, #8 Iterative, #9 Cognitive Load | Write tests first, small methods, one at a time |
| **/dr-qa** | #5 DoD verification, #10 Focused Review | Review one method at a time, check done criteria |
| **/dr-archive** | #8 Iterative verification + #10 Review (Step 0.5 reflection), #14 Structure (Step 2 archive doc) | Was the process followed? Hierarchical summaries for future context |

---

## QUICK RULE REFERENCE

| # | Rule | One-Liner |
|---|------|-----------|
| 1 | Stubbing | Break into 50-line stubs |
| 2 | TDD | Tests before code (Strict Mocking) |
| 3 | Method Size | Max 50 lines, 7-9 objects |
| 4 | Requirements | Context before coding |
| 5 | DoD | Explicit done criteria |
| 6 | Corner Cases | List boundaries first |
| 7 | Skeleton | Architecture before code |
| 8 | Iterative | One method at a time |
| 9 | Cognitive | 7+/-2 objects max |
| 10 | Review | Review one method only |
| 11 | Boundaries | State what's out of scope |
| 12 | Complexity | Verify AI can solve |
| 13 | Transaction | Explicit isolation levels |
| 14 | Structure | Hierarchical summaries |
| 15 | Prompts | Structured prompt creation |

---

## QUALITY CHECKPOINT

Before proceeding, ask:

```
[ ] Is this task decomposed into small units?
[ ] Do I have tests/DoD defined?
[ ] Is the architecture approved?
[ ] Am I focused on one thing?
[ ] Do I have the right context?
```

**If NO to any:** Stop and address before coding.

---

## COMMON MISTAKES

### DON'T
- Write code before tests
- Create methods > 50 lines
- Track > 9 objects per method
- Review entire features at once
- Start without clear requirements
- Skip corner case analysis

### DO
- Tests -> Code -> Review -> Next
- Keep methods small and focused
- One method at a time
- Define boundaries explicitly
- Document requirements upfront

---

## INCIDENT-NARRATIVE IN SAFETY GUARDS

When adding a non-obvious safety control (confirmation prompts, destructive-flag guards, permission checks, rate limits), cite in the runtime message the **incident ID + one-line effect** that motivated the control. This turns the guard into its own documentation: the operator sees *why* at the moment it triggers, without needing to open docs or git history.

### Why

A silent guard (`"Confirm? [y/N]"`) teaches nothing. Operators either learn its rationale by accident — when it fires on their own mistake — or they bypass it because they don't understand it. Either path erodes the guard over time.

A narrated guard carries the original lesson forward. Future operators, LLM agents included, learn from the incident without reproducing it.

### Pattern

```bash
echo "WARNING: --force on a live system will overwrite $CLAUDE_DIR"
echo "         TUNE-0003 incident: --force previously destroyed 9 runtime evolutions."
```

Two lines. First states the *what* (effect of proceeding). Second states the *why* (incident that exists because someone already proceeded).

### Rules

1. **One incident per guard** — cite the *founding* incident, not a list. If the guard accretes history, the most-costly incident wins.
2. **Quantify the effect** when possible (files lost, hours spent, users affected). "Destroyed 9 runtime evolutions" is clearer than "caused problems".
3. **Cite by ID, not by date** — IDs (`TUNE-0003`, `DEV-1156`) index into archives; dates rot.
4. **Keep it to ≤ 2 lines** in runtime output. Long narratives belong in docs; this is a reminder, not a lecture.
5. **Update the reference when superseded** — if a later incident replaces the original justification, rewrite both the guard and the archive cross-reference. Do not layer old and new together.

### When to skip

- Guards for completely self-evident constraints (typing `yes` to confirm destructive action). The prompt itself is the narrative.
- Compile-time or lint-level guards that never reach a human at runtime.
- Guards with no user-visible output (internal invariant checks).

### Exemplar

`install.sh:115` (TUNE-0004) — `--force` live-system warning cites TUNE-0003 by ID and quantifies the cost (9 files). The guard fires before any filesystem mutation; the operator has context before making the decision, not after.

---

## SCOPE DECISION FOR UNTRACKED LOAD-BEARING FILES

When a task's sweep phase touches files in an untracked-but-load-bearing part of a repository (e.g. `data/*.php` cards that the website reads at runtime but that were never `git add`-ed), make the governance call **before staging**, not during:

- **(a) Promote now** — commit the untracked files as part of the current task. Document in the commit message that promotion is incidental to the task, and list which files were newly tracked. Acceptable when the files are stable and the task naturally touches them.
- **(b) Defer** — create a separate governance task to audit and commit the untracked layer. Continue the sweep on already-tracked files only.

Do not start staging without choosing (a) or (b). Mixing tracked and newly-promoted files without a conscious decision creates hidden scope creep that is hard to audit later.

Rationale: TUNE-0013 Phase 5a promoted 26 untracked `datarim.club/data/*.php` files. The decision was correct but made at staging-time, not at sweep-planning-time — resulting in scope creep that had to be explained retroactively.

---

---

## OPERATOR-FIRST ATTRIBUTION

When a framework, vendor, or external service fails during integration, **default attribution is operator error** until proven otherwise.

### Rule

Before concluding "vendor bug" / "framework limitation" / "integration floor":

1. **Reproduce via minimal API** — curl the vendor endpoint directly, raw SDK call, docs example. If the minimal repro succeeds, the failure is on the operator's side (config, model choice, document format, timeout).
2. **Vendor blame requires BOTH:** (a) minimal repro confirms the failure, AND (b) reading the docs cannot flip it.
3. **Stop burning budget** — if retry loops are consuming tokens/money during the run, halt and diagnose before proceeding.

### Why

LTM-0002 first run ($20.32 wasted) blamed OpenRouter for Cognee's embedding failure, Claude Sonnet for JSON parse errors, and laptop RAM for Graphiti's absence. All three were operator errors:
- `curl` proved OpenRouter embeddings work (wrong LiteLLM prefix, not vendor protocol)
- Document pre-processing fixed JSON parse failures (not a language-level ceiling)
- arcana-dev has 62 Gi RAM (self-imposed laptop constraint)

### When to apply

Every integration failure during `/dr-do`. Before writing "framework X doesn't support Y" in a report, verify with a 5-minute minimal repro. The cost of a curl test is 5 minutes; the cost of a wrong attribution is a wrong article, a wrong vendor choice, and wasted operator budget.

### Exemplar

LTM-0002 R2: single `curl` to OpenRouter `/v1/embeddings` with `encoding_format="float"` → 1536-dim vector. Proved in 30 seconds that the vendor works. Cognee's failure was my `openai/` LiteLLM prefix routing to the wrong handler — fixed by switching to `openrouter/` prefix.

---

## DEPENDENCY ISOLATION

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

## DOCKER SMOKE TEST

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

## CLI CONNECTOR DOCKER PATTERN

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

---

*These principles reduce bugs by 40-50% and improve code quality by 30-50%.*
