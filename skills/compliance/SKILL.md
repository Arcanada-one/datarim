---
name: compliance
description: Post-QA hardening — detects task type (code, docs, research, legal, content, infra) and applies the matching verification checklist before archiving.
model: inherit
current_aal: 2
target_aal: 3
---

# Compliance — Adaptive Post-QA Hardening

Compliance is the final quality gate before archiving. It verifies that the work meets all stated requirements and standards. The checklist adapts to the task type.

## Deferral vs Inline-Ship Decision Heuristic

When a finding (Low / Medium severity) surfaces during compliance and a clean deferral target exists (a successor task that already owns the same surface), the default reflex is Path A: «document as caller-side contract, hand off to successor». This is the safe choice for high-blast-radius findings or those without a clean inline reduction.

But Path A carries a hidden cost: **caller-side contract is invisible closure debt**. The successor task carries the obligation, but the obligation is no longer linked to the original finding's context — the operator has to re-derive why the caller-side handoff exists when the successor task starts. If the successor expands into a multi-finding scope, the original handoff item silently grows in importance.

**Rule of thumb — prefer Path B (inline-ship) when ALL of the following hold:**

1. The fix is **≤100 LoC** of production code + tests (no architectural displacement).
2. The fix adds **≥2 behavioural tests** that exercise the previously-uncovered path.
3. The successor task has **no other depends-on** beyond this single obligation (so closing the handoff also closes a real downstream dependency, not just one of many).
4. The fix is **reversible by single-commit revert** (FB-6) and **does not change public API contracts** that other consumers depend on.

When any condition fails, Path A is correct. When all four hold, Path B is the lower-friction path — the operator gets one fewer cross-task handoff to track, and the successor task's scope is provably narrower at archive time.

**Operator override is the canonical escape hatch.** If compliance default-routes to Path A but the operator wants Path B (or vice versa), the override carries via `--focus-items` invocation of `/dr-do` — see Layer 3b FAIL-Routing CTA. Each override round MUST land in the init-task append-log (FB-2 / FB-5 traceability).

<!-- gate:history-allowed -->
Source: ARAS-0006 archive — F-2 (ReadlinePrompt deferral) and F-3 (caller-side canonicalize) initially Path A at compliance v1/v2; both operator-overridden to Path B in subsequent /dr-do rounds, closing ARAS-0024 obligations #1 and #2. Net effect: successor task's scope reduced from 3 items to 1. Second source: TUNE-0264 archive — PASS_WITH_NOTES (two functions slightly over 50-line cap) closed inline at /dr-compliance under Path B; accepted-risk register stayed empty by design.
<!-- /gate:history-allowed -->

---

## Step 0: Detect Task Type

Read `datarim/tasks.md` and `datarim/activeContext.md` to determine task type:

| Type | Indicators | Checklist |
|------|-----------|-----------|
| **Code** | Modified source code files (.js, .ts, .py, etc.) | Software Checklist (7 steps) |
| **Documentation** | Modified .md files in docs, guides, README | Documentation Checklist |
| **Research** | PRD mentions research, analysis, literature | Research Checklist |
| **Legal** | PRD mentions legal, compliance, terms, policy | Legal Checklist |
| **Content** | Modified posts, articles, blog content | Content Checklist |
| **Infrastructure** | Modified Docker, CI/CD, IaC, deploy configs | Infrastructure Checklist |
| **Mixed** | Multiple types | Apply relevant checklists from each type |

---

## Software Checklist (7 steps)

### 1. Change Set & PRD/Task Alignment
- Compare diff against PRD requirements and task acceptance criteria
- Flag: unimplemented requirements, out-of-scope changes, missing edge cases
- When a task's backlog entry states a root cause explicitly (e.g. "fixed-port collision", "missing index", "race on shutdown"), verify the stated cause against a live repro **before** accepting the implemented fix. A misidentified root cause in the backlog leads to misdirected rounds: the fix targets the wrong axis, passes a weak gate, and the real defect survives. A short manual repro at re-validate time surfaces the mismatch cheaply.

### 2. Code Simplification
- Check: functions >50 lines, deeply nested logic, duplicate code
- Apply Code Simplifier principles to recently modified code only

### 3. References and Dead Code
- Flag unused imports, variables, functions in changed files
- Verify no debug statements left in production code

### 4. Test Coverage
- Verify tests exist for all changed code paths
- Check: edge cases, error paths, boundary conditions
- **Quantitative-threshold AC enforcement.** When an Acceptance Criterion declares a numeric threshold (coverage %, latency budget, RPS, error rate, etc.), Compliance Step 4 (or Step 6 for runtime metrics) MUST execute the measurement tool and record the actual number. «Presumed met» is not an acceptable verdict for thresholded AC. If the measurement tool is absent on the host, install it (typically a one-line install via the project's package-manager-native tooling) before claiming PASS, or escalate the AC as BLOCKED back to `/dr-do`. When the AC genuinely cannot be measured yet (blocked on an external dependency, e.g. tooling not yet installed on the target host), defer it explicitly using the four-field waiver shape in `templates/coverage-deferral-clause.md` (status, gating dependency, follow-up condition, timestamp + owner) rather than carrying it forward as unstructured prose. Source: prior incident — AC-7 (≥80% line coverage) was carried as «presumed met» through `/dr-qa` PASS_WITH_NOTES; Compliance had to install the coverage tool and measure (actual 91.5%) to close the gap.
- **Agentic Entrypoint Wiring + Live-Run gate.** When the task ships a service/daemon/cron/agent whose declared purpose is to invoke an external CLI/LLM/subprocess (`claude -p`, `gh`, `aws`, …) and act on its output, Compliance MUST NOT pass it on a mock-only suite. Verify per `$HOME/.claude/skills/testing/live-smoke-gates.md` § Gate 7: (a) the *real* entrypoint (`__main__`/systemd `ExecStart`/cron) actually reaches the declared function — call-graph grep + runtime probe, an orchestrator/lane reachable only from tests is dead-code-in-prod ⇒ **NON-COMPLIANT** → `/dr-do`; (b) one **live** run of the agent against the real tool was performed, with the captured real output + observed side-effect recorded in the report. A kill-switch-OFF exit-0 probe proves the agent does *nothing* and does NOT satisfy this gate; an `evidence_type: empirical` wish marked met on mocks alone is a hard finding. Source: prior incident — orchestrator + repair lanes fully unit-tested but never wired to `cli.main`; `claude -p` never ran in prod; QA passed on mocks and proposed archive; operator caught the unwired entrypoint.

### 5. Linters and Formatters
- Run project linters and formatters
- Flag: lint errors, formatting inconsistencies
- **CI linter-scope check.** When the project's CI scopes the linter narrower than the full repo (e.g. `ruff check src/ scripts/` but not `tests/`), and compliance finds the unscoped directories dirty, recommend widening the CI scope to the full tree (`ruff check .` or explicit `src/ tests/ scripts/`) as part of the cleanup. Compliance is the wrong place to discover a narrowly-scoped linter — a narrow CI scope produces avoidable cosmetic notes in every QA cycle. Fix the scope at the source, not just the dirty files.

### 6. Test Execution
- Run the full test suite, report pass/fail counts
- **Pre-existing branch failure discrimination.** When tests fail in a CI-faithful run, check whether each failure was present before the task's commit: `git log --oneline <base>..HEAD -- <failing-test-file>`. If the violation predates the task (none of the task's commits touched the failing file), document it as "pre-existing branch issue, not introduced by task commit" and do NOT treat it as a task-scope blocking verdict. The task's own diff must be clean — failures from unrelated branch history or parallel-session dirty files are advisory, not verdicts.
- **Workspace-hygiene auto-classification (regression-invariant tests).** A common failure shape in a shared workspace is a *regression-invariant* test — a test asserting that some scope directory is gate-clean (e.g. "`skills/` scope is English-only", "`agents/` scope has no private IDs"). When such a test fails, do not hand-write a discrimination note each time. Run the deterministic git-based classifier with the failing test's scope directory:
  ```sh
  bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/classify-bats-failure-scope.sh" \
       --repo <framework-repo> --base <base-ref> --scope <scope-dir> [--scope <scope-dir> ...]
  ```
  The classifier runs `git log <merge-base>..HEAD -- <scope-dir>` per scope. A scope with **zero** task commits in the range is labelled `pre-existing` (exit 0) — the failure is foreign / parallel-session noise; record the classifier's verdict verbatim and do NOT treat it as a task-scope block. A scope that **did** receive task commits is labelled `regression` (exit 1) — it stays a real, blocking regression and a real regression is never masked. The helper fails **closed** (exit 2) when a scope's git range cannot be evaluated, so an undeterminable scope is never auto-classified as foreign. This replaces the per-archive manual discrimination note for regression-invariant failures; the per-file manual check above still applies to failures that are not scope-shaped.
<!-- gate:history-allowed -->
Prior incident: two test failures traced to pre-task commits and foreign dirty hunks — neither introduced by the task under compliance review. Recurrence: the same hand-written discrimination note for a regression-invariant test whose scope had no task commits surfaced repeatedly across tasks until it was made deterministic via the classifier above.
<!-- /gate:history-allowed -->
- **Report-cited-SHA resolution probe (fabrication vs stale-clone).** When a QA or compliance report cites commit SHAs or merge-request numbers, do not trust them on faith nor reject them as fabricated without a probe. Run `git cat-file -t <sha>`; if the object is absent locally, run `git ls-remote origin` and `git fetch origin <branch>` read-only, then verify the diff against `FETCH_HEAD`. A SHA absent **both** locally and on the remote is a genuine fabrication finding — **NON-COMPLIANT**. A SHA absent locally but present on the remote branch is the expected stale-clone case in a remote-first project (the work was pushed from another machine and the local clone never fetched): fetch read-only and verify the actual diff — never block, never reject. Verify against `FETCH_HEAD`, do not check out, so a shared clone parked on another task's branch stays undisturbed.
<!-- gate:history-allowed -->
Prior incident: a QA report cited two commit SHAs invalid on the local clone (`git cat-file` reported them as unknown objects); both resolved on the remote feature branch and the implemented work was real — the local clone was simply stale in a remote-first workflow. Compliance fetched the branches read-only and verified the diffs against `FETCH_HEAD`.
<!-- /gate:history-allowed -->

### 7. CI/CD Impact Analysis
- Detect: new dependencies, changed env vars, new build steps
- Flag: breaking changes to build pipeline, missing migration steps
- **Stale-runtime advisory (non-blocking).** When the task touched a shipped script (`scripts/lib/*.sh`) or skill (`skills/*/SKILL.md`), the change is live only where it was committed. Run the shared detector and surface its output verbatim so multi-machine consumers are reminded to update each install: `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-stale-runtime.sh" --repo <framework-repo> --range <base>..HEAD`. Single source of truth (same script as `/dr-archive` Step 0.48); advisory only — it never gates the compliance verdict.
- **Stale-base merge-result gate (`git`-only).** Before reporting any apparent change in PR diff vs `origin/<base>` as a "regression", check whether the diff is a side-effect of `origin/<base>` advancing past the branch's merge-base rather than a branch-side edit. If `git diff <merge-base>..HEAD -- <file>` is empty for a file that nonetheless appears in `git diff origin/<base>..HEAD -- <file>`, simulate the actual 3-way merge: `git merge-tree $(git merge-base HEAD origin/<base>) HEAD origin/<base>`. If the simulated tree preserves the upstream change in question, the apparent diff is a no-op on merge — record this in the report and do NOT block the archive on a rebase requirement. Source: prior incident — a feature PR appeared to revert an upstream baseline-hardening fix that landed mid-flight; merge-tree simulation confirmed the fix was preserved by 3-way merge, deflating a needless rebase cycle.
- **Stale test-count classification (non-blocking).** When a commit message claims N/N tests pass but a live re-run of the test suite reports M/M with M > N, and the additional tests are verifiably present in the commit (grep confirms the test definitions exist in the committed files), classify the discrepancy as informational non-blocking — a normal polish-test addition committed after the run that produced the message. Do NOT treat it as a re-commit trigger or a compliance failure; record the live count (M/M) as the authoritative figure and note the original message count for traceability.

### Loop-guard pre-emptive operator handoff (attempt 2 vs attempt 3)

`cta-format` § Loop guard escalates after **3 same-layer fails**. The default automatic re-run between attempts 1 and 2 is appropriate only when the verdict could plausibly change without external action — for example, when a flaky test was re-run, when an upstream timing dependency might have caught up, or when the operator may have acted between attempts.

When a probe set is **deterministic** (`gh pr view` PR states, `git rev-parse origin/main` HEAD, live `/health` endpoints, validator stdout) AND **state delta vs the previous attempt is empty across all probes**, attempt 2 carries zero information. The verdict cannot change without operator action.

In that case Compliance MUST, on attempt 2:

1. Capture the empty-delta finding in the v2 report (one-line delta table is sufficient).
2. Pre-emptively formulate a handoff question to the operator (FB-8 — surface only the question that actually blocks safe forward progress), **rather than** running attempt 3 with the same probe set.
3. Loop-guard counter remains at 2/3 until external action (operator or autonomous-by-delegation) produces a real state delta.

Anti-pattern caught by this rule: identical NON-COMPLIANT verdicts at v1 + v2 produced by re-running the same `gh pr view` / `curl /health` set 23 minutes apart with no merge in between. The runtime probes are cheap, but the compliance turn (context, narration, validator append-log) is not — and the operator gets a noisy «attempt 2 of 3» banner that obscures the actual blocker.

Source: prior incident — a multi-repo task ran compliance v1+v2 within 23 minutes; both returned identical Layer-4 NON-COMPLIANT verdicts with state delta ∅ on all 5 runtime probes (PR states, main HEAD, live `/health`, expectations validator). Attempt 3 resolved only when the operator explicitly delegated the blocking mechanical action under FB-1..FB-5 + autonomous-ops authorization, not via further probe re-runs. Provenance: see `documentation/how-to/evolution-log.md` for the archive entry that motivated this rule.

---

## Documentation Checklist

### 1. Completeness
- All required sections present, no placeholders (TBD, TODO)

### 2. Accuracy
- Technical claims correct, code examples work, versions current

### 3. Consistency
- Terminology consistent, formatting follows style guide, heading hierarchy logical

### 4. Cross-References
- Internal links resolve, external links valid, bidirectional where needed

### 5. Audience Appropriateness
- Language matches audience, prerequisites stated, examples progressive

### 6. Operator-Only Runbooks
- A runbook whose steps are operator-only (hard-gated actions: store consoles, production deploys, secret rotation) carries an explicit HARD-GATED marker on its first content line

### 7. Doc-Only QA Stub (narrow class)
When the task ran the `/dr-auto` L1 doc-only fast-path and produced a `qa-stub` artefact (`datarim/qa/qa-stub-{TASK-ID}.md`), that stub satisfies the QA-presence requirement for this compliance run. Compliance MUST NOT emit the "QA report absent" advisory for this class. Verify only that the stub file exists and records at least the style/banlist check and the cross-reference grep outcomes. Any other task class (code, infra, research, content, legal, or a doc task that did not go through the fast-path) still requires a full `/dr-qa` report; absence of that report remains an advisory as before.

---

## Research Checklist

### 1. Methodology
- Stated and followed, data sources identified, scope appropriate

### 2. Citation Completeness
- All claims cited, sources authoritative and current, format consistent

### 3. Argument Coherence
- Logical flow, conclusions follow evidence, counter-arguments acknowledged

### 4. Scope Compliance
- Within defined scope, out-of-scope noted for future work

---

## Legal Checklist

### 1. Jurisdictional Compliance
- Correct jurisdiction referenced, applicable laws current

### 2. Definitions and Terms
- All specialized terms defined, used consistently

### 3. Structural Integrity
- Clause numbering sequential, cross-references correct

### 4. Rights and Obligations
- Clear for all parties, liability limited, termination defined, dispute resolution present

---

## Content Checklist

### 1. Factual Accuracy
- Claims verified (factcheck skill), statistics sourced

### 2. AI Pattern Removal
- Passes humanize audit, author's voice preserved

### 3. Platform Requirements
- Meets target platform specs (length, format, media, SEO)

### 4. Editorial Standards
- No spelling/grammar errors, tone matches audience

---

## Infrastructure Checklist

### 1. Configuration Accuracy
- Correct for target environment, no hardcoded secrets

### 2. Rollback Plan
- Changes reversible, procedure documented, previous state backed up

### 3. Monitoring and Alerts
- Monitoring configured, alert thresholds set, dashboards updated

### 4. Security
- Least-privilege, SSL/TLS correct, access controls appropriate

### 5. Discovery Probe Verification
- For infra tasks referencing external state (GitHub org contents, DNS records, server inventory, cloud project structure) — verify assumptions against the **live API** during `/dr-prd`, NOT at `/dr-do`. Inventory mismatches caught late cost creative/planning effort. Example: `.meta` planned 13 repos when only 7 existed in the GitHub org.
- **Same-name repo is not proof of source (site/service source-recovery).** For a task that must reproduce a live site/service from source, the repo NAMED after the domain/service may NOT be its source. Prove the source with a candidate build compared against the live target BEFORE plan-time, and search by CONTENT (manifest `name` field, asset set, deploy-script target path, directory structure) across ALL org repos — not only the same-named one. A same-name repo that exists but does not reproduce the live build is a false source; the real source is often a differently-named repo. A do-stage candidate build from the wrong repo yields a false "source-lost" verdict that a content-based hunt later has to correct — pay the content-hunt cost at plan-time instead. Cross-check: a byte-identical bundle filename (content-hashed asset such as `main.<hash>.js`) shared between the candidate build and the live target is the strongest single parity signal for hash-named single-page-app output.
- For tasks planning DNS/CDN provider rule changes: probe the provider's **zone inventory AND plan-tier feature availability** at `/dr-prd` before writing the solution section. Structural assumptions that look like subdomains may be separate zones (each needing its own rule), and a rule-expression function available on one plan tier may be absent on another — both invalidate a written plan in one API call's worth of discovery. Also probe the **API token's permission scopes** against the exact endpoints the plan intends to call; a token valid for reads may lack the edit scope for the rule phase, forcing an architecture change mid-execution.
- For tasks migrating data between storage instances (ClickHouse, Postgres, Mongo): the source instance MUST be identified via a **live probe of the actual writer service's env** (`docker inspect <writer> --format '{{.Config.Env}}'`, then resolve any service-alias to its container) at `/dr-plan` time — NOT inferred from indirect evidence (query-log timestamps, last-seen INSERT patterns, prior-session recon notes, or inventory-file comments). Indirect evidence names a hypothesis; the live env probe names the fact. A writer pointed at a Docker-network alias (e.g. `clickhouse:8123`) may resolve to a co-located local container rather than the remote host the inventory implies.
- **Unblocked-task DoD-precondition probe.** For a task that was unblocked by another (`blocked_by`, a backlog note like "after X closes", or "earliest: <date>"), the task's DoD was authored **before** the blocking task ran — and the blocking task may have changed the very state the DoD assumes. At `/dr-do` start, probe whether the DoD's precondition still holds: if the DoD names a live resource (a running service to back up, an instance to repoint, a port to bind) that the parent task may have stopped, moved, or retired, verify that resource's current state with a live probe before implementing. When the parent invalidated the precondition (e.g. the DoD says "back up the live DB nightly" but the parent stopped the DB and froze its data), surface the divergence and reconcile the DoD with the operator (or autonomously under FB-1..FB-5 when the correct reading is unambiguous) **before** executing the stale DoD. Mechanically running an outdated DoD wastes a cycle and ships the wrong outcome. This is distinct from the root-cause check in Software Step 1 (which validates a *stated cause*) and from the hypothetical-trigger probe (which validates a *named symptom*): here the DoD was correct when written and drifted over time.

### 6. Nested Git Repos Cleanliness
- For workspace-level infra tasks (file-sync, backup, mass-rename) scan ALL nested git repos, not only the workspace root:
  ```sh
  find . -maxdepth 6 -name .git -type d -exec dirname {} \;
  ```
- For each: `git status --porcelain` + `git rev-list --count @{u}..HEAD` (uncommitted + unpushed).
- Flag as Open Item if any nested repo has uncommitted changes or unpushed commits — they may be invisible production fixes that file-sync silently propagated (see evolution-log: Email Agent had 7 file deltas + 1 unpushed commit invisible until `/dr-archive` clean-git check).

### 7. File-Sync Configuration Audit (when task touches Syncthing/rclone/rsync/Dropbox/Disk Arcana setup)
- Load `$HOME/.claude/skills/file-sync-config/SKILL.md`.
- Run pre-flight inventory `find` per the skill's checklist BEFORE confirming compliant.
- Verify ignore patterns cover ALL discovered classes (.venv/__pycache__/target/*.db/.next/.build/etc.).
- Verify nested git repos either fully excluded or documented as «read-only mirror».
- Source: prior incident — first .stignore set (28 patterns) missed 11 classes; 1 sync-conflict materialized + 60+ accumulated before audit caught it.

### 7b. Bulk-Replace Token-Collision Pre-Scan (when task performs bulk text replacement across ≥10 files)
- BEFORE executing the replacement, run a token-collision pre-scan: grep the target file set for every substring of the replacement source/target that could collide with unrelated entity names (product names, service names, acronyms sharing a stem). A replacement of a domain suffix or brand stem can silently corrupt look-alike tokens (one extra/missing character class of defects).
- Any collision found → HIGH finding: switch to surgical per-file replacement with explicit per-file diff verification; never a single global substitution.
- AFTER the replacement, verify with a residual-diff audit: normalize the intended swap out of the diff and confirm zero residual added/removed lines (content comparison, not just exit codes).

### 8. Scheduler-Unit Antipattern Check (when task deploys recurring scheduler units — e.g. systemd timers, cron entries, launchd plists)
- Validate every modified scheduler unit on the host with the OS's native validator (e.g. `systemd-analyze verify <unit>`, `crontab -T`, `plutil -lint`). Non-zero exit → block compliant.
- For timer-style units: verify the unit does NOT carry a hard dependency on the work-unit it triggers. A timer that hard-requires its own service stops together with the service when an operator runs the service manually — the timer goes silent, the next scheduled fire is lost, and the failure is invisible (no failed unit, no alert handler invoked). Cross-host static check: <!-- gate:example-only -->`grep -E "^Requires=" *.timer` MUST be empty per host where recurring units are deployed.<!-- /gate:example-only -->
- Verify catch-up semantics for missed fires: persistent-fire flag set so a host coming back from outage / a unit re-enabled after stop runs the previously missed schedule. Without it, a single missed fire silently disappears.
- Recommend smoke procedure via the timer interface (start the timer, let it trigger the unit) rather than starting the work-unit directly — the latter can mask the antipattern above.
- Source: prior incident — three production hosts shipped scheduler timers with the antipattern; daily fire missed on one host, detected only via downstream artefact count (snapshot count on the storage target), not via any in-host alert.

### 9. Multi-Root Success-Criterion Verification (when a wish / AC names ≥2 filesystem roots)

When an expectation's success criterion or an acceptance criterion names two or more distinct filesystem roots that must all satisfy the same property (e.g. a code repository AND a separate registry/docs tree, or a service tree AND its sibling configuration tree), the verification MUST grep every named root independently. A repo-local helper script proves only the repo it scans; it is not evidence for the other roots.

- Enumerate the roots the criterion names. Run the criterion's check against each root separately and record per-root evidence (one grep/probe result per root).
- Do NOT accept a single repo-local helper (a checker shipped inside one of the roots) as proof for the whole criterion — that helper is blind to the other roots by construction.
- A clean result on root A plus an unchecked root B is a partial verification, not a pass. Surface root B explicitly as unverified rather than inferring it from root A.
- Source: prior incident — a "no working-branch-X references anywhere in trees A and B" criterion was verified only by the in-repo checker living in tree A; tree B (a separate registry) still carried working references and reached QA as a blocker.

### 10. Concurrent-Session Check for Shared-Infra Mutation
- Before mutating access to a resource that other sessions/agents may touch in parallel (shared DB, shared config, shared runner, shared NAS/Vault credential), check for concurrent activity first: `grep`/`ls` active `datarim/.auto-mode-active*` markers across sessions, and note any other in-flight task on the same resource (backlog/PRD cross-reference).
- If a concurrent session is active on the same resource, surface the conflict risk before mutating rather than after — do not silently overwrite state a parallel session may depend on.
- Rationale: real incidents motivated this step — a dev-compose cutover once killed prod because the mutation ran without checking for a concurrent session on the same shared DB; separately, two tasks restored admin access to the same NAS in parallel without a concurrent-session check, risking an SSH-provisioning conflict.

---

## Output

Render the compliance report via the canonical structure declared in `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md`. The report carries:

- Frontmatter: `task_id`, `date`, `verdict` (COMPLIANT / COMPLIANT_WITH_NOTES / NON-COMPLIANT), optional `scope`.
- Four operator-facing top sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги». <!-- allow-non-ascii: russian-archive-template-section-names-cited-from-template -->
- An audit addendum under a `---` horizontal rule carrying `### Step-by-step verdicts` (the 7-step per-step table), `### Remaining risks`, `### Related`.

The four top sections answer «что просил оператор» and «что подтвердили / что осталось» in plain Russian — apply the banlist from `skills/human-summary/banlist.txt`. The audit addendum carries the technical surface (status table, risk list, cross-links) and MAY wrap ASCII-heavy lines in `<!-- gate:literal -->` fence. <!-- allow-non-ascii: russian-operator-quoted-archive-section-purpose-cited-from-template -->

Save to `datarim/reports/compliance-report-{task_id}.md` if the directory exists, otherwise present in chat. Filename suffix on re-runs: `-v2`, `-v3`, … (one new file per `/dr-compliance` invocation).
