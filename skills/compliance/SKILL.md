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

### 2. Code Simplification
- Check: functions >50 lines, deeply nested logic, duplicate code
- Apply Code Simplifier principles to recently modified code only

### 3. References and Dead Code
- Flag unused imports, variables, functions in changed files
- Verify no debug statements left in production code

### 4. Test Coverage
- Verify tests exist for all changed code paths
- Check: edge cases, error paths, boundary conditions
- **Quantitative-threshold AC enforcement.** When an Acceptance Criterion declares a numeric threshold (coverage %, latency budget, RPS, error rate, etc.), Compliance Step 4 (or Step 6 for runtime metrics) MUST execute the measurement tool and record the actual number. «Presumed met» is not an acceptable verdict for thresholded AC. If the measurement tool is absent on the host, install it (typically a one-line install via the project's package-manager-native tooling) before claiming PASS, or escalate the AC as BLOCKED back to `/dr-do`. Source: prior incident — AC-7 (≥80% line coverage) was carried as «presumed met» through `/dr-qa` PASS_WITH_NOTES; Compliance had to install the coverage tool and measure (actual 91.5%) to close the gap.

### 5. Linters and Formatters
- Run project linters and formatters
- Flag: lint errors, formatting inconsistencies

### 6. Test Execution
- Run the full test suite, report pass/fail counts

### 7. CI/CD Impact Analysis
- Detect: new dependencies, changed env vars, new build steps
- Flag: breaking changes to build pipeline, missing migration steps
- **Stale-base merge-result gate (`git`-only).** Before reporting any apparent change in PR diff vs `origin/<base>` as a "regression", check whether the diff is a side-effect of `origin/<base>` advancing past the branch's merge-base rather than a branch-side edit. If `git diff <merge-base>..HEAD -- <file>` is empty for a file that nonetheless appears in `git diff origin/<base>..HEAD -- <file>`, simulate the actual 3-way merge: `git merge-tree $(git merge-base HEAD origin/<base>) HEAD origin/<base>`. If the simulated tree preserves the upstream change in question, the apparent diff is a no-op on merge — record this in the report and do NOT block the archive on a rebase requirement. Source: prior incident — a feature PR appeared to revert an upstream baseline-hardening fix that landed mid-flight; merge-tree simulation confirmed the fix was preserved by 3-way merge, deflating a needless rebase cycle.

### Loop-guard pre-emptive operator handoff (attempt 2 vs attempt 3)

`cta-format` § Loop guard escalates after **3 same-layer fails**. The default automatic re-run between attempts 1 and 2 is appropriate only when the verdict could plausibly change without external action — for example, when a flaky test was re-run, when an upstream timing dependency might have caught up, or when the operator may have acted between attempts.

When a probe set is **deterministic** (`gh pr view` PR states, `git rev-parse origin/main` HEAD, live `/health` endpoints, validator stdout) AND **state delta vs the previous attempt is empty across all probes**, attempt 2 carries zero information. The verdict cannot change without operator action.

In that case Compliance MUST, on attempt 2:

1. Capture the empty-delta finding in the v2 report (one-line delta table is sufficient).
2. Pre-emptively formulate a handoff question to the operator (FB-8 — surface only the question that actually blocks safe forward progress), **rather than** running attempt 3 with the same probe set.
3. Loop-guard counter remains at 2/3 until external action (operator or autonomous-by-delegation) produces a real state delta.

Anti-pattern caught by this rule: identical NON-COMPLIANT verdicts at v1 + v2 produced by re-running the same `gh pr view` / `curl /health` set 23 minutes apart with no merge in between. The runtime probes are cheap, but the compliance turn (context, narration, validator append-log) is not — and the operator gets a noisy «attempt 2 of 3» banner that obscures the actual blocker.

Source: prior incident — a multi-repo task ran compliance v1+v2 within 23 minutes; both returned identical Layer-4 NON-COMPLIANT verdicts with state delta ∅ on all 5 runtime probes (PR states, main HEAD, live `/health`, expectations validator). Attempt 3 resolved only when the operator explicitly delegated the blocking mechanical action under FB-1..FB-5 + autonomous-ops authorization, not via further probe re-runs. Provenance: see `docs/evolution-log.md` for the archive entry that motivated this rule.

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

---

## Output

Render the compliance report via the canonical structure declared in `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md`. The report carries:

- Frontmatter: `task_id`, `date`, `verdict` (COMPLIANT / COMPLIANT_WITH_NOTES / NON-COMPLIANT), optional `scope`.
- Four operator-facing top sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги». <!-- allow-non-ascii: russian-archive-template-section-names-cited-from-template -->
- An audit addendum under a `---` horizontal rule carrying `### Step-by-step verdicts` (the 7-step per-step table), `### Remaining risks`, `### Related`.

The four top sections answer «что просил оператор» and «что подтвердили / что осталось» in plain Russian — apply the banlist from `skills/human-summary/banlist.txt`. The audit addendum carries the technical surface (status table, risk list, cross-links) and MAY wrap ASCII-heavy lines in `<!-- gate:literal -->` fence. <!-- allow-non-ascii: russian-operator-quoted-archive-section-purpose-cited-from-template -->

Save to `datarim/reports/compliance-report-{task_id}.md` if the directory exists, otherwise present in chat. Filename suffix on re-runs: `-v2`, `-v3`, … (one new file per `/dr-compliance` invocation).
