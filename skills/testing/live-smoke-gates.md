---
name: testing/live-smoke-gates
description: Live verification gates for raw SQL, cross-container orchestration, and user-switch deployments. Mocked tests cannot satisfy these.
---

# Live Smoke-Test Gates

Five related gates that fire when the failure mode lives in the *runtime environment*, not in code logic. Mocks cannot satisfy them — only a real run against real systems can.

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

Reference incident: a raw query intended to hit `stats` (mysql5) was injected on the `bi_aggregate` client (mysql8). Unit tests mocked the Prisma client and passed green. Production returned "table not found" on first request. Root cause: `PrismaService` vs `PrismaBiService` were both valid injections for the DI container, and the type-checker could not distinguish them for a `$queryRaw` call.

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

Reference incident: 241 unit tests passed and NestJS clone code merged to main. First-ever live Docker clone (during `/dr-qa` weeks later) surfaced 3 independent runtime bugs: `wp_clone_script_dev` was non-executable in git index (`100644`), SWC version of the script used hardcoded `-hdb` hostname with no `db` service in Docker, and MySQL 8 PHP clients hit `self-signed certificate` errors against local MySQL 8 containers. Zero of these were detectable in unit tests.

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

Reference incident: switching cron from root to an agent user caused 3 simultaneous regressions: (1) data directory owned by root → PermissionError, (2) Gemini CLI OAuth creds not in new HOME → API_KEY_INVALID, (3) `except (OSError, ...)` caught PermissionError as "transient network failure" → silently swallowed. 54 emails were fetched (marked as read in Gmail) but never delivered to Telegram. All found by operator hours later, not by deployment verification.

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

### Coverage probe (group-aggregation features)

For features whose acceptance metric depends on **group-aggregated** data (entity-grouping, topic-clustering, batched reflection, multi-row aggregation, etc.) — **before** the N=1 smoke, run a **coverage probe**: query the underlying corpus to count how many groups satisfy the «≥N members» threshold the aggregation requires. If the count is zero or near-floor (1-2 groups), the chosen acceptance metric is statistically dominated by one group's signal and likely cannot exceed the baseline on this corpus. Two responses:

1. **Flag in the implementation plan** that the AC may not exceed baseline на этом corpus, and ensure the plan has an explicit **branch-trigger** (DIAGNOSE / re-corpus / A/B-alternative) для the miss path. This makes a numerical miss an expected, handled outcome rather than a panic-reroute.
2. **If the trigger does not exist in the plan**, escalate before pilot — either expand the corpus, lower the AC, or add the branch-trigger.

**Reference incident:** a reflect-job creates meta-facts only from entity-groups with ≥2 source chunks. Pilot corpus had 188 entities but **187 single-chunk** — only 1 group qualified. Resulting 4-fact pool was statistically insufficient for the chosen recall@5 ≥ baseline+5pp threshold; AC-2 missed numerically. The plan *did* include a DIAGNOSE branch-trigger, so the miss became an expected handled outcome rather than blocked archive. A coverage probe before the pilot would have flagged the floor case in advance.

### Verdict

- Gate required + N=1 smoke passed + intermediate state asserted → **proceed with bulk run**.
- Gate required + smoke skipped, only final output checked → **bulk-run cost wasted on first attribution mistake**, restart from item #1 after fixing resolver. This is the whole point of the gate.
- Gate required + smoke revealed misattribution → fix the resolver/normalizer first, re-run smoke, then bulk.

### Reference incident

41-chunk pilot re-ingest hit acceptance gate on primary metric (`recall@5 = 0.667` ≥ target 0.5), but two supplementary DoD failed (extraction-rate 17 % vs target 80 %, manual `as_of` filter missing). Single root cause: the entity resolver preferred generic entity names over a more specific task-id pattern, so events for archive chunks were attached to the wrong canonical entity and the `as_of` filter treated them as timeless. A single N=1 smoke on one archive chunk before the ~1200-second pilot would have surfaced the misattribution; instead the gap was discovered after the full benchmark cycle. Cost: one full pilot + benchmark + analysis loop, recoverable but avoidable.

---

## Gate 5: Container Env-Var Freshness After Deploy

**Who this applies to:** any deploy where environment variables changed (new secret added, key rotated, config flag flipped) and the runtime is a long-running container or service. The failure mode is silent: the deploy reports green, the new value sits in the on-disk config file, but the running process started from a stale snapshot and never sees it.

### Why this fails silently

Container orchestrators that recreate on image change (`docker compose up -d --build`, `kubectl rollout restart`) load env vars at create time. If the image hash didn't change but the env file content did, the orchestrator may keep the existing container and skip env reload. The on-disk config file looks correct; the running process behaves as if the change never happened. Inspection of the *file* gives a false-positive; only inspection of the *process* surfaces the truth.

### When the gate is mandatory

The gate **must** fire whenever:

- A deploy adds, removes, or changes an env var consumed by the running service (API key, feature flag, connection string, URL).
- The deploy command did not include an explicit recreate flag (`--force-recreate`, `kubectl rollout restart`, `systemctl restart`).
- The new env var is consulted lazily at request time (most are) — boot-time crashes would otherwise self-report.

### What a passing gate looks like

After deploy, before declaring success:

1. **Verify on disk:** `grep <NEW_VAR> /path/to/.env` returns the expected line.
2. **Verify in process:** `docker exec <container> sh -c 'env | grep <NEW_VAR>'` (or k8s/systemd equivalent) returns the same value. **This is the load-bearing check** — file presence is necessary but not sufficient.
3. If step 2 returns empty or stale value: force recreate (`docker compose up -d --force-recreate <service>`) and re-run step 2 before retesting application behaviour.

### Verdict

- File present + process env shows new value → proceed with smoke.
- File present + process env empty/stale → **deploy was effectively a no-op for this change**; recreate before any further verification.
- File absent → deploy script bug; do not recreate, fix the deploy step first.

### Reference incident

A connector deploy added `GROQ_API_KEY` to PROD `.env`; CI ran `docker compose up -d --build` and reported success. `grep GROQ /srv/apps/.../.env` returned the new key (file write OK), but `docker exec ... env | grep GROQ` returned empty — the container was not recreated by the build step because the image hash already matched. Application traffic to the connector endpoint would have failed `auth_error` despite the "successful" deploy. Closed by `docker compose up -d --force-recreate model-connector`. Generic Compose gotcha — applies to any new env var on any project in the ecosystem.

---

## Gate 6: UI Trigger → Cross-Datasource Write

**Who this applies to:** any change that ships a UI affordance (button, menu item, link, form submit, drawer action) which causes a server-side write to a data store the unit-test suite does not exercise. The failure mode lives between the click and the row — neither the frontend test (which mocks the API) nor the backend test (which mocks the data layer) crosses the seam, and the runtime gap is invisible until live data is inspected.

### Why mocks don't satisfy it

Frontend tests mock the API client at the fetch/HTTP boundary, so the click is observed but the request is never sent. Backend tests mock the data-layer client at the repository boundary, so the request is observed but the row is never written. Both layers report green. The end-to-end path — click → wire request → handler → real client → real write → durable row — is never traversed in any automated suite. A wrong data source, a wrong column, a missing audit-trail row, or a silent transaction rollback can all pass every test and fail every live click.

### When the gate is mandatory

The gate **must** fire (live click + post-condition read in the target store, recorded) when a change ships:

- A UI action (button, menu, drawer submit, keyboard shortcut) whose handler resolves to a write on a data store that the test environment does not bind (separate physical instance, separate schema, separate tenant, separate region).
- A status badge / progress indicator backed by a column that the same UI action writes — the read and the write are on the same store but on different code paths, and a stale-read race is invisible to mocks.
- An audit-trail / event-log row written as a side effect of the action — silent drop is the canonical failure mode.

### What a passing gate looks like

Before marking the change as done, the developer (or `/dr-qa` Layer 4) must record in the QA report:

1. **The click sequence** — exact UI path traversed (page, element, value entered, confirm dialog if any), captured in a live browser session against the deployed build, not in jsdom.
2. **The target store coordinates** — host / database / table / row identifier (no credentials). Same physical instance / schema as production where feasible; staging is acceptable if it shares the engine version and schema with prod.
3. **The post-condition read** — exact query and result: the column values just written, the audit row created, the count delta. Inspecting the UI status badge does not substitute for inspecting the row — the badge is itself under test.
4. **The before/after delta** — capture a pre-click read so that the diff is unambiguous; «row exists after the click» is necessary, «row did not exist before the click» is the additional bit that closes the timing assumption.

### Why the read-back step matters separately from the click

A click that yields a 2xx response means the API accepted the request, not that the row landed. Many failure modes return 2xx and silently drop the write: wrong data source binding, missing transaction commit, conditional `WHERE` clause that excluded the intended row, schema column rename that the ORM tolerated. Only the live read against the target store closes the loop.

### Verdict

- Gate required + live click + live read + delta recorded → **Layer 4 PASS** on this dimension.
- Gate required + only mocked tests run → **Layer 4 FAIL**. The button works on every machine that has no database; that is the whole point of the gate.
- Gate required + live click without the target-store read-back → **Layer 4 FAIL**. The badge can lie; the row cannot.
- Gate required + read-back reveals missing or wrong row → diagnose before marking done; do not paper over with a UI-only retry that masks the data-layer regression.
