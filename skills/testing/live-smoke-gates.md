---
name: testing/live-smoke-gates
description: Live verification gates for raw SQL, cross-container orchestration, and user-switch deployments. Mocked tests cannot satisfy these.
---

# Live Smoke-Test Gates

Five related gates that fire when the failure mode lives in the *runtime environment*, not in code logic. Mocks cannot satisfy them — only a real run against real systems can.

---

## Current-State Auth Probe

**Who this applies to:** any live smoke test that crosses an authentication boundary — HTTP API key, OAuth client credential, JWT issuer/audience, signed request, mTLS cert, secrets-manager-issued token, or equivalent. This subsection is a pre-flight requirement for **every** gate below, not a standalone gate.

### Why it matters

Smoke failures across an auth boundary surface ambiguously: a stale or rotated credential looks identical to a capability regression at the application-layer error ("401", "403", "500", empty response). Without a current-state probe of the credential before the capability test, triage budget is spent on the wrong layer. The pattern compounds during an in-flight architectural transition — e.g. a migration roadmap toward a centralised identity provider — where the legacy and new issuers may both mint credentials in parallel and the smoke harness can pick the wrong one silently.

### What a passing probe looks like

Before invoking the capability under test:

1. **Hit an auth-scoped, capability-cheap endpoint with the same credential** — pick the cheapest call that fails fast on auth without exercising the capability under test (token-introspection endpoint, JWKS endpoint, secrets-manager `lookup` call, CLI auth-status command, key-metadata endpoint).
2. **Use a distinct exit code / sentinel on auth failure** — different sentinel for auth-probe failure vs capability regression. Triage automation and CI dashboards must distinguish them; an "auth expired" condition counted as a capability red is wasted alert budget.
3. **Record the probe result alongside the smoke result** — both lines in the QA report: `auth_probe: PASS (issued <iso8601>, expires <iso8601>)` and `capability_probe: <result>`.

### Verdict

- Probe required + probe passed → proceed with the gate that fired.
- Probe required + probe failed (expired / revoked / wrong issuer) → fix the credential first, do not run the capability test. A capability red on a stale credential is a false signal.
- Probe required + probe skipped → the gate's verdict is **unverified** — capability red and capability green are both unreliable.

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

### Allowed exception — canonical liveness probe

A raw-query `SELECT 1` (or an equivalent vendor liveness ping such as Redis `PING`, Kafka `metadata` fetch, or a no-op gRPC `Health/Check`) qualifies for a **waiver** from Gate 1 when ALL of the following hold:

1. The query is **read-only and non-parametric** — a fixed sentinel that returns one constant row / value, no user input, no schema dependency.
2. The **same client instance** (same DI binding, same datasource URL, same auth credentials) is already exercised end-to-end by a passing `/health` (or equivalent liveness) endpoint in the deploy pipeline (post-deploy smoke or pre-archive health curl).
3. The dependency on the liveness endpoint is **documented** in the task-description's § Implementation Notes or § Known Outstanding State / Operator Handoff with a one-line cross-reference.

**Rationale.** A 1-row sentinel against a connection that is already validated by a green `/health` probe in the deploy pipeline does not add new contract surface. Re-running the full Gate 1 ritual (record exact command, host, datasource, row count) would be process-tax without incremental signal — the liveness endpoint already records all four with stronger semantics (real DI graph, real network path).

**This is NOT a waiver for** any query that selects from a user table, parses a payload field, or depends on schema shape — those remain under Gate 1 mandatory.

<!-- gate:history-allowed -->
Reference incident: opsbot `CommandsService.healthProbe()` uses `$queryRaw\`SELECT 1\`` as the canonical liveness check; the Prisma client running this call is the same one exercised by `GET /health` before any command is dispatched (ARCA-0009 M2). Strict Gate 1 would have FAILed `/dr-compliance` for canonical liveness — the exception lets the trivial sentinel pass while still gating real raw-SQL paths.
<!-- /gate:history-allowed -->

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

1. **Flag in the implementation plan** that the AC may not exceed baseline on this corpus, and ensure the plan has an explicit **branch-trigger** (DIAGNOSE / re-corpus / A/B-alternative) for the miss path. This makes a numerical miss an expected, handled outcome rather than a panic-reroute.
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

---

## Gate 7: Agentic Entrypoint Wiring + Live-Run

**Who this applies to:** any task that ships a service/daemon/cron/agent whose declared purpose is to *invoke an external CLI, LLM, or subprocess and act on its output* — code reviewers, self-healing agents, ingest workers, orchestrators that spawn `claude -p` / `gh` / `aws` / any tool. The canonical trigger is "an agent that runs a tool and does something with the result."

### The two failure modes this gate catches

A unit suite with injected/mocked dependencies can be 100% green while the shipped artifact does **nothing** in production, via two distinct gaps:

1. **Unwired entrypoint (dead-code-in-prod).** The orchestrator / repair-lane / business-logic module is written and unit-tested, but the actual entrypoint the runtime invokes (`__main__`, the systemd `ExecStart`, the cron command, the queue consumer) never *calls* it. The module is reachable only from tests. Production runs the entrypoint, the entrypoint runs a thin stub, and the declared function never executes. Mocks cannot catch this because the test imports the module directly — it never goes through the real entrypoint.

2. **Never-run-live (the LLM/CLI is always mocked).** Every test injects a fake `spawn_fn` / mock subprocess, so the *real* `claude -p` (or `gh`, `aws`, etc.) is never invoked even once. The silent-failure class these agents exist to surface (CLI exits 0 on error, stdout-error sentences, missing PATH, missing credential, wrong working dir) lives entirely in the real invocation. A green mock suite proves the *logic* around the tool, never that the tool runs.

### Why mocks structurally cannot satisfy this

The whole point of an agent that drives a CLI/LLM is the integration boundary. Mocking `spawn_fn` is mocking the thing under test (violates the entry skill's Mocking Rules). And importing the orchestrator in a test proves the orchestrator works — it says nothing about whether `main()` reaches the orchestrator. Both gaps are invisible to the test suite by construction.

### What a passing gate looks like

Before any wish/AC of the form "the agent diagnoses/repairs/processes via <tool>" may be marked **met** (and before `/dr-qa` Layer 4 or `/dr-compliance` may pass an agentic task):

1. **Entrypoint-reachability proof.** Trace the *real* entrypoint to the declared function with a static call-graph walk AND a runtime probe. Concretely: `grep` that the entrypoint module imports and calls the orchestrator/lane (not just that the orchestrator exists), AND run the real entrypoint with the feature enabled and confirm — via logs/audit/side-effect — that the declared function was actually entered. If `main → run_pass` and `run_pass` never calls `orchestrator.run_loop`, the wish is **missed**, not met, regardless of how many orchestrator unit tests pass.

2. **One live invocation against the real tool.** Run the agent **once, for real**, with the kill-switch ON and the tool actually present, against a realistic input. Capture the real tool's stdout/exit and the agent's resulting side-effect (audit record, notification, MR, file change). A `claude -p`/CLI agent must show one real `[CLI_START]`→result→action cycle in the captured run. Record the exact command, the tool version, the captured output, and the side-effect in the QA report. Pair with the **Current-State Auth Probe** above (the tool's credential must be live) and **Gate 3 / PATH** (the tool must be on the service's PATH, not just the login shell's).

### Verdict

- Entrypoint reaches the function (proven both ways) + one live tool-run with the real side-effect observed → gate PASS, wish may be **met**.
- Entrypoint does NOT reach the function (orchestrator/lane unwired) → wish **missed**; `/dr-qa` Layer 4 = FAIL, route to `/dr-do`. This is not a partial — the declared capability does not exist in prod.
- Entrypoint reaches it but no live tool-run was performed (only mocks) → wish at most **partial** with the gap stated; an `empirical` evidence_type wish is **not met** on mocks alone (the per-wish block must carry a real command + real tool output, never a mock assertion).

### Caution — live-run on prod fans real notifications

A live agentic run on a host whose notification channels are configured will send **real** messages to the operator's production Slack/Telegram. A verification ESCALATION (e.g. a deliberately low budget exhausting) lands in the live operator channel and reads as an incident. Before a live agentic run on prod: (a) prefer a test channel / dry-run flag, or (b) warn the operator first, and (c) post a clarification to the same channel afterward. The notification *is* a real outward-facing action (init-task Hard-gated Action Boundary), not a local side-effect. Source: DEV-1462-FU — a `MAX_ITERS=2` verification run emitted a real `[ESCALATION] budget exhausted` to the Aether Code Review Slack channel; harmless but noisy, required an operator-facing clarification.

### Reference incident

DEV-1462-FU self-healing reviewer technician: orchestrator + KB/config/service/code repair lanes were fully written and unit-tested (115+ green tests, all with injected `spawn_fn`/mock GitLab), but `cli.main → run_pass` only performed the Phase-1 snapshot diagnose+notify — `orchestrator.run_loop` and every `repair_*` lane were **never called from the entrypoint**, and `claude -p` was **never invoked in prod** even with `ENABLED=1` + `LANES=all`. QA marked the `empirical` "cron agent diagnoses via claude -p and heals" wish **met** on the mock suite + a kill-switch-OFF exit-0 probe (which proves the agent does *nothing*), and proposed archive. The operator caught it: "ты даже агента не включил, ни одного тестового запуска". Root cause: no gate required (a) entrypoint→function reachability or (b) one live `claude -p` run before an agentic wish could pass.

---

## Measurement hygiene: a trailing pipe masks the binary's exit code

When a live smoke verifies a **CLI binary's exit code** (e.g. «281-char input → non-zero exit, 279-char → exit 0»), do NOT pipe the binary's output to `tail` / `head` / `grep` while reading `$?` — the shell reports the exit status of the **last** command in the pipeline, which is the pager, not the binary. A genuinely-failing case then reads as exit 0 and the gate passes on a false negative.

```sh
# WRONG — $? is tail's status, always 0
mybin --reject-case | tail -5; echo "exit=$?"

# RIGHT — redirect, then read the binary's own status
mybin --reject-case > /tmp/out 2>&1; echo "exit=$?"
# or, if you must pipe:
mybin --reject-case | tail -5; echo "exit=${PIPESTATUS[0]}"   # bash/zsh
```

This is the silent-failure-detection class turned inward: the same «exit 0 hides a real failure» trap that the gate exists to catch in the code under test also bites the reviewer's own measurement. Always re-run a surprising «exit 0» without the pipe before recording a PASS. Source: a reviewer-side `… --dry-run | tail` reported exit 0 for a known-reject CLI case; the no-pipe re-run showed the correct exit 1.


## Tag-triggered workflows ship unexercised — load-lint + one live tag-run

A CI workflow gated on `on: push: tags: ['v*.*.*']` is never exercised by branch pushes or PRs — only an actual version tag triggers it. Such a workflow can ship completely broken and sit unused until the first real release, then fail when it matters most.

Before archiving a task that authors or edits a tag-triggered workflow:

1. **Load-lint with `actionlint`.** GitHub reports a workflow that fails to load only as a generic "This run likely failed because of a workflow file issue" with no line number, and registers phantom `failure`-in-0s runs on every push. `actionlint` names the exact rule and line. The recurring fatal class: a **job-level `name:` referencing the `env` context** — `env` is not in the availability list for `jobs.<id>.name` (only `github`/`inputs`/`matrix`/`needs`/`strategy`/`vars`), and using it breaks the whole workflow's load. Declare custom self-hosted runner labels in `.github/actionlint.yaml` so label warnings don't mask real errors.
2. **Run it once live.** Push a throwaway test tag (or exercise the `workflow_dispatch` path) and confirm the workflow actually loads, the intended jobs run, and gated jobs (prod deploy) correctly skip. A clean local lint is necessary but not sufficient — runner availability, missing CLIs on self-hosted runners (`gh`/`aws`/`jq` not installed → `command not found`, exit 127), and secret wiring only surface in a real run.

**When to apply.** Any task that ships or edits a workflow triggered only by tags / releases / schedules — events that normal CI (branch push / PR) never fires. Skip for `push`/`pull_request` workflows, which every commit already exercises.
