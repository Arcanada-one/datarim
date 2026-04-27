---
name: testing/live-smoke-gates
description: Live verification gates for raw SQL, cross-container orchestration, and user-switch deployments. Mocked tests cannot satisfy these.
---

# Live Smoke-Test Gates

Three related gates that fire when the failure mode lives in the *runtime environment*, not in code logic. Mocks cannot satisfy them — only a real run against real systems can.

---

## Gate 1: Raw-SQL / Cross-Datasource

**Who this applies to:** any change whose correctness depends on a *real* external system behaving a specific way — not on code logic that can be proven in isolation. The canonical trigger is raw SQL and cross-datasource code, but the principle generalizes.

### When the gate is mandatory

The gate **must** fire (live smoke test is required, not optional) when a change touches any of:

- `$queryRaw`, `$executeRaw`, `raw()`, `sequelize.query()`, `db.exec()`, or any path that bypasses the ORM's type-checker and schema validation.
- Multi-datasource projects where more than one client / connection / schema exists and a specific call must target a specific one (e.g. reads from `stats` vs `bi_aggregate`, from `primary` vs `replica`, from tenant A vs tenant B).
- Migrations, DDL changes, or any code that runs against a schema the unit tests don't represent.
- Queue / message / webhook code where the "contract" is what the receiving system accepts, not what the sender thinks it sends.

### Why mocks don't satisfy it

A wrong-client `$queryRaw` **compiles clean** and **passes mocked tests** — because the mock doesn't know which datasource the real call would hit. The error only appears at runtime, against real data, in a code path the test suite cannot reach.

Reference incident: **DEV-1156** (aio-v2). A raw query intended to hit `stats` (mysql5) was injected on the `bi_aggregate` client (mysql8). Unit tests mocked the Prisma client and passed green. Production returned "table not found" on first request. Root cause: `PrismaService` vs `PrismaBiService` were both valid injections for the DI container, and the type-checker could not distinguish them for a `$queryRaw` call.

### What a passing gate looks like

Before marking a change with raw SQL / cross-datasource semantics as done, the developer (or `/dr-qa` Layer 4d) must:

1. Run the query **against the real target datasource** — dev DB, staging DB, or a disposable container matching the prod engine and schema. Not a generic Postgres. Not "any MySQL". The *same* engine version and the *same* schema as the target.
2. Record in the QA report:
   - The exact command or invocation used (`npx prisma db execute ...`, `psql -h ... -c "..."`, etc.).
   - The datasource hit (host / database / schema — no credentials).
   - The result: row count, expected-empty confirmation, or the error message.
3. In multi-datasource code, **verify the right client was used** — read the import, trace the DI container, confirm by output of the smoke test, not by inspection alone.

### Verdict

- Gate required + gate passed + recorded → **Layer 4 PASS** on this dimension.
- Gate required + gate not run → **Layer 4 FAIL**, not `PASS_WITH_NOTES`. This is the whole point.
- Gate required + gate failed (unexpected result) → stop, diagnose, do not merge.

---

## Gate 2: Live Docker Smoke Test Before Archive

**Who this applies to:** any task that orchestrates external shell scripts, performs file I/O across container boundaries, or makes cross-container HTTP / RPC calls (e.g. NestJS HTTP client → PHP container → bash script → mysql client). Mocked unit tests cannot catch this class of bug — the failure mode lives in the runtime environment, not in the code logic.

### When the gate is mandatory

The gate **must** fire (live Docker end-to-end run is required, not optional) when a change touches any of:

- An HTTP client that calls another container's API which then `shell_exec`s a script (file permissions, exec bit, hardcoded hostnames inside the script will not appear in any unit test).
- Code that depends on a specific MySQL/Postgres/Redis client version inside a specific container talking to a specific server version (TLS/SSL defaults, auth plugins, character sets — all environmental).
- Volume-mounted config files (`.my.cnf`, `nginx.conf`, `wp-config.php`) where syntax errors are runtime-only.
- Anything that reads/writes filesystem paths inside containers — exec bits, ownership, mount points, `extra_hosts` DNS aliases all fail at runtime, not at compile time.

### Why mocks don't satisfy it

A mocked HTTP client returns whatever the test sets up. The real client would have to:
- resolve a hostname (which may not exist in Docker DNS),
- send a request the receiving server actually accepts (auth headers, content-type),
- trigger a script that has the right exec bit and uses the right database hostname,
- which connects to a database with the expected SSL/TLS configuration.

Each of those layers can silently break without a single unit test failing.

Reference incident: **DEV-1169 follow-up** (`reflection-DEV-1169-followup.md`). 241 unit tests passed and the NestJS clone code merged to main. First-ever live Docker clone (during `/dr-qa` weeks later) surfaced 3 independent runtime bugs: `wp_clone_script_dev` was non-executable in git index (`100644`), SWC version of the script used hardcoded `-hdb` hostname with no `db` service in Docker, and MySQL 8 PHP clients hit `self-signed certificate` errors against local MySQL 8 containers. Zero of these were detectable in unit tests.

### What a passing gate looks like

Before marking a change of this class as DoD-complete, the developer (or `/dr-qa` Layer 4) must:

1. Run the actual end-to-end action **in Docker, against real containers**, with no manual hacks like `docker exec ... chmod +x` or `docker exec ... echo "alias" >> /etc/hosts`. If you needed those to make it work, they belong in the committed `Dockerfile` / `docker-compose.yml` / repository, not in the test session.
2. Record in the QA report: the exact command invoked, the containers it traversed, the post-conditions verified (file count delta, DB row count delta, target artifact existence — not just exit code).
3. Verify the legacy callee actually succeeded by inspecting *post-conditions*, not just the parent's reported success flag. Legacy Yii / PHP / bash chains often return `success:1` when the script "ran" even if it produced no output. Check that the expected DB exists, the expected files were copied, the expected row counts match.

### Verdict

- Gate required + live Docker run passed + post-conditions verified → **Layer 4 PASS** on this dimension.
- Gate required + only mocked tests run → **Layer 4 FAIL**. The whole point of the gate is that mocks lie.
- Gate required + live run revealed env hacks needed (chmod, hosts edit, .my.cnf rewrite) → fix them in the committed Docker config, re-run, then PASS. Hacks in a session are not a passing gate.

---

## Gate 3: Post-Deploy Smoke Gate (User-Switch Deployments)

When a deployment changes the **runtime user** (e.g. root → dedicated service user), run one full application cycle as the new user **before switching cron/systemd** to that user. A clean exit under the old user proves nothing about the new user's permissions, HOME directory, config file access, or tool authentication.

### When the gate is mandatory

The gate fires when a deployment does any of:
- Switches cron or systemd service from one user to another.
- Changes file ownership on config/data directories.
- Creates a new system user to run existing code.

### What to verify

1. **One complete cycle** as the new user: `su -s /bin/bash newuser -c '/path/to/run.sh'` — must exit 0 with clean output.
2. **All external tool auth paths**: CLIs invoked via subprocess (Gemini, Claude, gcloud, etc.) store credentials in `~/.config/` or `~/.toolname/`. If HOME changed, creds are missing.
3. **File I/O permissions**: data directories, log files, lock files, temp dirs — all must be writable by the new user.
4. **Exception hierarchy**: `PermissionError` is a subclass of `OSError` in Python. If outer handlers catch `OSError` for network errors, they will silently swallow file permission failures. Explicitly exclude `PermissionError`, `FileNotFoundError`, `IsADirectoryError`.

### Why "deploy then switch cron" fails

Reference incident: **EMAIL-0001**. Switching cron from root to `email-agent` caused 3 simultaneous regressions: (1) data directory owned by root → PermissionError, (2) Gemini CLI OAuth creds not in new HOME → API_KEY_INVALID, (3) `except (OSError, ...)` caught PermissionError as "transient network failure" → silently swallowed. 54 emails were fetched (marked as read in Gmail) but never delivered to Telegram. All found by operator hours later, not by deployment verification.

### Passing gate

- Run one cycle as new user + verify clean output → **deploy proceeds**.
- Cycle fails → fix perms/creds/handlers, re-run cycle, then deploy.
- Cycle not run → deployment is **not verified**, regression risk accepted explicitly.

---

## Gate 4: N=1 Smoke Validation Before Bulk Ingest/Transform

**Who this applies to:** any task that runs a parser, resolver, normalizer, or disambiguator across a corpus (re-ingest, batch migration, import, ETL, embedding refresh, bulk reclassification). The failure mode lives in the *attribution layer* — the bulk run completes "successfully" while every record is linked to the wrong target, and the gap is invisible until downstream evaluation.

### When the gate is mandatory

The gate **must** fire (one-item dry-run is required, not optional) before any bulk run that:

- Depends on an entity-resolution / record-linkage / normalization step where multiple candidates exist (task-id pattern vs generic name, canonical FK vs free-text label, primary vs alias).
- Persists foreign-key relationships derived from a parser (regex, NER, LLM extractor).
- Computes downstream features (filters, ranks, joins) keyed off the resolved attribution.
- Will be hard or expensive to re-run (paid LLM calls, multi-hour pipeline, side-effect-heavy persistence).

### Why mocks and unit tests don't satisfy it

Unit tests verify the parser produces *some* answer for a representative input. They don't verify the answer points to the *intended* target row in the database, because the disambiguation tie-breaker depends on what other entities already exist in the namespace at runtime. The bug class — wrong attribution that compiles green and persists silently — only manifests against real data.

### What a passing gate looks like

Before launching the bulk run:

1. Pick **one known-representative item** from the corpus where the correct attribution is unambiguous (a chunk that names a canonical task-id, a row with a clear-cut foreign key, etc.).
2. Run the full ingest/transform path on that item against the real datastore.
3. **Assert intermediate state, not just final output**:
   - The persisted row points at the *expected* FK / canonical entity (not a generic alias).
   - Downstream filters that key off this attribution behave as expected (e.g. `as_of` / category filter excludes/includes per ground truth).
4. Record the smoke result (item id, expected target, actual target, downstream filter check) before proceeding.

### Verdict

- Gate required + N=1 smoke passed + intermediate state asserted → **proceed with bulk run**.
- Gate required + smoke skipped, only final output checked → **bulk-run cost wasted on first attribution mistake**, restart from item #1 after fixing resolver. This is the whole point of the gate.
- Gate required + smoke revealed misattribution → fix the resolver/normalizer first, re-run smoke, then bulk.

### Reference incident

**LTM-0012** (2026-04-26). 41-chunk pilot re-ingest hit acceptance gate on primary metric (`recall@5 = 0.667` ≥ target 0.5), but two supplementary DoD failed (extraction-rate 17 % vs target 80 %, manual `as_of` filter missing). Single root cause: the entity resolver preferred generic entity names over a more specific task-id pattern, so events for archive chunks were attached to the wrong canonical entity and the `as_of` filter treated them as timeless. A single N=1 smoke on one archive chunk before the 1209-second pilot would have surfaced the misattribution; instead the gap was discovered after the full benchmark cycle. Cost: one full pilot + benchmark + analysis loop, recoverable but avoidable.
