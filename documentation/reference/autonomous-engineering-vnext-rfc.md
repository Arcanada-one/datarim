# Datarim vNext: Goal-Driven Autonomous Engineering, Future Dependency DAG, and Pre-PR Evidence

Status: DRAFT RFC, 2026-11-22. **Not implemented, approved, released, or adopted by ecosystem consumers.** Phase-0 reference checker lives in this draft branch. Scope: Datarim first; Scrutator and Arcanada teams only after the reviews required by the adopter's approval policy (section 7a) and independent evidence.

## 1. Evidence and baseline

The operator supplied a post advocating 24/7 autonomous engineering: intake and parking poor tickets, review of the plan before coding, separate implementer and reviewer model providers, sandboxed execution, automatic repair, conflict resolution, complete lint/type/test/mutation/security checks before PR, and a risk/dependency/rollback PR packet. A supplied follow-up proposes automatic A-to-B goals, Lean 4, Clojure, and "5 sigma". The linked Claude Artifact was not accessible during this research; additional unprovided comments, implementation details, and commercial success claims were not verified.

Datarim main at 8e738a4f583cb96904c41573ca5334dc148ec252 (VERSION 4.12.9) already contains /dr-auto, /dr-orchestrate, /dr-plan, /dr-qa, /dr-compliance, frozen acceptance and evidence, provenance, spec/framework graphs, model routing, and reflection. Extend these existing components. Never create a second task authority, duplicate framework graph, or replacement unreviewed agent.

## 2. Intended behavior

One bounded delegated engineering task proceeds from a measured point A toward a measured point B:
intake -> goal admission -> dependency/source analysis -> frozen plan -> independent plan review -> isolated implementation -> pre-PR validation and repair -> signed candidate evidence -> PR -> exact-head integration and approval-policy gates -> build-once delivery -> independent served-source readback -> outcome measurement -> validated reusable learning.

Every interruption has a durable outcome: PARKED_NEEDS_INPUT, BLOCKED with exact reason, EXPIRED with owner, REFUSED with rule, or RESUMABLE with source pins. No agent invents missing goals or secretly weakens a gate.

Acceptance (P1): a fault-injection test interrupts the run at least once in every state of section 4 (process kill, lease expiry, executor loss, missing input) and then reads back, from the durable store and not from process memory, one record per interruption with one of the five outcomes and its required field (reason, owner, rule or source pins). An interruption with no readable record, or a record without its required field, is FAIL. Until P1 runs that test the claim is NOT_MEASURED.

## 3. Contracts

### GoalContract/v1

Required: goal_id; owner; parent_goal; North Star metric ID; metric definition with unit, numerator, denominator, event population and authoritative observation source; baseline value and observation timestamp; target value, direction and deadline; minimum practically meaningful improvement; time/budget/scope/privacy limits; acceptance cases; task dependencies; causal assumptions; policy revision and approved task-generation scope. Missing baseline or target => proposal, not an admitted executable task. Automatic ticket creation occurs only inside owner-delegated authority and within existing Muneral for Arcanada. Candidate goals have explicit do-nothing cost, uncertainty and owner disposition.

### TicketIntakeReceipt/v1

Frozen source digest, source tracker and key, canonical work-item ID, dedupe fingerprint, goal link, quality findings (desired outcome, scope, reproducible context, testability, risk, dependencies), state/owner/actionable missing input, idempotency key. Poor tickets are parked and answered, not hallucinated into implementable specs. Jira integration is optional: Datarim is tracker-agnostic.

### FutureImpactGraph/v1

Typed nodes: goal, requirement, ticket, module/file, interface/data contract, test, artifact, release target, business observable. Edges: depends_on, implements, touches, verifies, produces, deploys_to, measures, blocks. Provenance on each edge: declared, statically discovered or actually observed; repo/commit/hash, confidence and uncertainty. Unknown edge != absent edge. Detect cycles, owner boundaries, untested changed files, dangling nodes, downstream dependents, parallel collisions, critical-path obligations. Overlay existing Datarim spec-graph/framework-graph rather than copying them. Freeze the graph before execution and refresh when the source tree or plan changes.

### PlanReviewReceipt/v1

Freeze GoalContract, PRD, acceptance, risk, graph, change list and rollback approach under one plan digest before code. Independent vendor/provider reviewer records receipt and concrete findings; the implementation provider cannot approve itself. Provider string in self-reported JSON is not an independently authenticated model identity; real gate requires source-bound signed or externally witnessed receipts. Re-review after material plan changes. L1/L2 use concise plan only where existing risk/complexity policy permits; L3/L4 keep full PRD and the review required by the approval policy (section 7a).

### CandidatePrePRReceipt/v1

Bind task, goal/plan/acceptance digests, source repository, base/head/tree, lockfiles, toolchain, sandbox image and policy revision, test-selection graph, all required commands and results, measured logs and digests, model providers, reviewer identity, unresolved findings, rollback and downstream consumers. Required lanes: lint, typecheck, unit, integration, contract, security/secrets, mutation/property where risk requires, E2E where applicable, deployability smoke. Distinguish PASS, FAIL, SKIPPED, NOT_MEASURED, NOT_APPLICABLE with documented authority. Only a real trusted executor may attest actual runs. A self-authored "pass" is never acceptable release proof.

### VerifiedLesson/v1

Failure signature, root cause, code/test before and after, exact source digest, independent confirmation, outcome and recurrence, tenant/namespace, TTL and supersession, review under the approval policy (section 7a) before it changes policy. Reflection is candidate data until verified and adopted. Retrieved memory must never execute itself or authorize credentials/deployment.

## 4. Engineering state machine

PROPOSED -> QUALIFIED -> PLAN_FROZEN -> PLAN_REVIEWED -> IMPLEMENTING -> PREPR_CHECKING -> PREPR_VERIFIED -> PR_OPEN -> HEAD_REBOUND -> MERGE_ADMITTED -> RELEASED -> PUBLIC_READBACK_VERIFIED -> OUTCOME_MEASURED -> LEARNING_PROPOSED/ACCEPTED.

Alternate PARKED, BLOCKED, EXPIRED, REJECTED and ROLLED_BACK retain full negative evidence. Retry is bounded, idempotent, source-fenced and budgeted. Rebase/merge/base drift invalidates stale review or execution unless all covered inputs and obligations are provably equivalent.

## 5. Execution architecture

- Multiple tasks: one owner lease each; limited WIP; separate bounded branches/worktrees/workspace; collision and interface-impact detection before parallel runs.
- Stage executor: disposable VM or equivalently isolated sandbox; no production credentials, no shared privileged files/host caches, no network by default; bounded CPU, time, model tokens and budget; enforced exit/status and append-only audit. A GitHub self-hosted label alone is NOT a sandbox.
- Developer and reviewer: different model providers or BLOCKED/explicit approved exception, never silent self-review. Fallback handles vendor outages without changing model quality, privacy or authorization floors. Acceptance: fallback targets come only from a pinned allow-list in the routing policy; each entry declares its data-handling class, authorization scope and minimum model tier, and a fallback to a target whose declared class, scope or tier is below the primary's is refused and recorded (P2 negative control). Equivalence of model quality between providers is NOT_MEASURED; P4 and the experiment report defect and rework rates per provider so a drop is visible.
- Repair: diagnose -> patch -> targeted recheck -> full required verification; preserve every failed attempt, no disabling tests, rewriting baselines or reclassifying required lanes after red evidence.
- PR packet: original objective, baseline/target and North Star, frozen plan, future/observed dependency graph, source SHA, complete attested pre-PR test matrix, independent review findings, risk, consumer impact, migration, rollback, and post-PR/production outstanding checks.
- Release: build once in unprivileged context; bind output digest to immutable source+toolchain; after merge perform only obligations whose source/coverage identities permit reuse plus environment/privilege-specific checks, the approvals required by the approval policy (section 7a), atomic switch, private-data denial, purge and independent first-public-healthy readback. Never replace required CI/production checks with an agent's self-asserted local log.

### Important deployment constraint

Moving expensive tests before PR is valuable, but cannot guarantee instantaneous deployment. PR base updates, lockfile/toolchain changes, protection policy and production environment conditions may require new verification. Merge-to-public-ready SLO starts at the **original merge time**; keep attempts with no workflow run and late dispatch, not just successful deploy job durations. The pre-merge CPU time and production SLO are different metrics. Shared GitHub runner pools must never let untrusted PR jobs reach production writable stores. Acceptance: the P2 and P3 negative control below; until it runs the claim is NOT_MEASURED. Required source and cache rights are not granted by this RFC.

## 6. Lean 4, Clojure and statistics

Lean 4 is an OPTIONAL formalization pilot for small critical deterministic invariants: allowed state transitions, no unchecked promotion, DAG acyclicity, never treating NOT_MEASURED as PASS. Bind proof to executable implementation version and test against independent mutants. It does not prove external APIs, an LLM answer or a deployed service works.

Clojure is OPTIONAL only after a measured prototype shows transaction/concurrency advantage over the existing Python/shell, SQLite/Postgres state machine and immutable event log. Its STM and reactive Agents are useful tools, not proof of an autonomous AI engineer. Avoid a gratuitous language rewrite.

No general "5 sigma software correctness" target. Deterministic invariants use exhaustive/model/property/formal checking; empirical engineering gains need preregistered baseline, exact population/denominators, effect size, confidence intervals, independent repeats and confounder control. A p-value alone neither proves causality nor commercial benefit.

## 7. Phased deliverables and acceptance

**P0: isolated read-only pilot, draft branch.** One stdlib validator consumes proposed goal+file/test dependency DAG and claimed run receipts, verifies exact local Git base/head/tree, clean tree, nontrivial A->B, acyclic dependencies, complete changed-file/test coverage, frozen plan digest and distinct declared providers. Result is STRUCTURALLY_READY, NOT actual test/provenance acceptance; always trusted_execution=NOT_VERIFIED and release_eligible=false. Local fixture: real Git feature commit + an executed unittest, 14 checker tests including negative mutation controls. This proves bounded guard behavior only.

**P1: integrate existing contracts.** Datarim /dr-plan -> shared goal + future graph; /dr-qa and /dr-compliance -> existing immutable acceptance/provenance evidence. Do not duplicate current check-live-evidence, spec-graph-gate or framework-graph. Changes to acceptance/source/graph invalidate downstream approval. Exercise current full Bats and shell/python regressions.

**P2: trusted pre-PR executor.** Ephemeral sandboxed full suite with deterministic source and command capture, independent cross-provider review and signed attestation. Negative controls: forged test, skipped required arm, poisoned package/toolchain cache, network, secret, stale head, changed lockfile, wrong review identity, missing API, and a fallback to a model provider below the declared floor -> fail closed. Zero privilege escalation. Production-store negative control: a job started from an untrusted PR (fork or unreviewed branch) attempts to write each production writable store the deployment uses (deploy credential, production database, release cache, signing key, served web root); every attempt must be denied, the denial recorded, and the job's runner must show no mount or credential for those stores. One successful write is FAIL.

**P3: actual autonomous PR gate.** Controlled orchestrator cannot create PR unless the trusted receipt is complete; native PR CI validates exact candidate and security policy before reusing evidence. Branch protection and required checks remain mandatory; merge approval follows the approval policy (section 7a). Test correct/changed head and base, tampered artifacts, denied network and missing checks, and repeat the P2 production-store negative control on the PR runner pool. No duplicate task registry.

**P4: one production service canary.** Run three distinct authorized production activations, preserving original merge clocks and all failed/no-run attempts; measure first independently observed healthy expected SHA, no forbidden private content, cache state, recovery safety and rollback. Need all actual Muneral DoD checks, not just three observations.

**P5: publish Datarim and propagate.** After full required tests, trusted review and the existing release gate: VERSION/CHANGELOG and a signed GitHub tag/release created from the merged main commit by the repository's release workflow (a product release in its own repository, not an external publication), README and install/upgrade/migration, EN/RU docs, and the datarim.club changelog published by push to main and its deploy pipeline, with externally verified served bytes. Any announcement on social networks or other external sites goes only through the adopter's mandated publishing channel (Publisher in Arcanada). Next, after review under the approval policy, Scrutator KnownFix retrieval and memory namespace integration with its recall security gates, then selected Arcanada engineering consumers behind pinned versions/flags. Each repo has its own PR/CI/readback; no automatic fleet rewrite.

### 7a. Approval policy (product knob)

`approval_policy` is an adopter setting, recorded in the policy revision that every receipt binds:

- `owner_approval`: a named human owner approves plan and merge. Available to adopters who want it; Datarim does not require it.
- `blind_agent_review`: an independent agent reviewer from a different provider reviews the exact head without seeing the author's verdict; its verdict counts only for that head.

Arcanada value: `blind_agent_review`, with no human gate on any phase, per Arcanada decision DEC-AUP-0010 ("no gates on the operator"; human review steps become blind agent review). In Arcanada the only hard gates are the Supreme Directive and the Publisher mandate. Acceptance: the P3 gate reads `approval_policy` from the pinned policy revision; a fixture with `blind_agent_review` must admit a merge with no human approval present, and a fixture with `owner_approval` must refuse it.

### 7b. Invariants every phase preserves

1. Precedence: the Supreme Directive (Rules of Robotics) overrides this RFC, any adopter policy and any agent instruction. On conflict the agent refuses, records the rule, and the task ends REFUSED.
2. Graph-verified change: in Arcanada, merge and release admission require the existing ChangeAdmissionReceipt/v1 for the exact head (DEC-AUP-0008): impact set computed, every affected entity re-verified by the verifier for its edge type, tri-valued verdicts. FutureImpactGraph/v1 and CandidatePrePRReceipt/v1 are inputs to that receipt, never a replacement; an empty impact set is a prediction to explain, not an approval. Acceptance: the P3 gate refuses a candidate whose ChangeAdmissionReceipt/v1 is missing, names a different head, or holds a FAIL verdict.
3. Destructive-command floor: the host safety hook (Jev in Arcanada) stays installed and enforcing in every executor, sandbox and orchestrator; no phase disables, bypasses or relaxes it. Acceptance: a P2 negative control issues a blocked destructive command inside the executor and expects the floor's refusal.
4. Publication route: external publication goes only through the adopter's mandated channel (Publisher in Arcanada); own sites publish only by push to main and their deploy pipeline; the GitHub tag/release is a product release made by the repository's workflow. No phase posts directly to an external service.

### 7c. Per-phase reversal

| Phase | reverse_if (any one) | Rollback action |
|-------|----------------------|-----------------|
| P0 | the checker reports STRUCTURALLY_READY for a fixture its negative controls expect to fail, or any consumer reads its output as release evidence | delete the draft branch or revert the pilot commit; nothing outside the branch depends on it |
| P1 | the full Bats and shell/python regression suite turns red on the integration, or an existing evidence check (check-live-evidence, spec-graph-gate, framework-graph) changes its verdict on an unchanged input | revert the integration PR; flag `vnext_goal_graph` off; existing /dr-plan, /dr-qa and /dr-compliance behaviour returns unchanged |
| P2 | any negative control in P2 passes when it should fail, a production-store write succeeds, or the executor needs a production credential | stop the executor, revoke its runner registration and credentials, revert the executor PR; candidates fall back to native PR CI |
| P3 | the gate admits a candidate without a complete receipt, admits a stale head, or refuses a valid candidate in two consecutive cases | flag `vnext_pr_gate` off and revert the gate PR; merges follow the existing branch protection, required checks and approval policy |
| P4 | a canary activation serves an unexpected SHA, exposes forbidden private content, or recovery fails | roll the service back to the previous released build by its existing rollback, keep every attempt record, stop further activations |
| P5 | a release fails served-bytes readback, the upgrade breaks a pinned consumer, or a consumer reports a regression traced to the release | publish a new patch release that restores the previous behaviour (never delete or re-tag a published release); consumers stay on or return to their pinned previous version |

## 8. Experiment protocol

Pre-register a comparison of baseline Datarim and vNext on comparable tasks (initial target 30 paired/randomized tasks per arm if practical; report precise sample size and stratification). Primary: median and p90 ticket-ready -> PR-ready, and original merge -> first healthy public readback. Secondary: escaped defects, rework, missed dependency edges, false-green/false-block, token+runner cost, human review minutes, incident/rollback rate, and recurrence of verified known fixes. Report denominators, confidence intervals and minimum practical improvement. Initial hypothesis: >=20% shorter median PR-ready without measurable quality/security regression. A P0 fixture is NOT evidence of this effect, and a deployment without independent exact-SHA public readback remains NOT_MEASURED.

Stop on policy/credential breach, increased critical defects, unbounded costs or degraded accuracy. Rollback consists of independent feature-flag/tool-source revert and product release rollback, never deletion of failures or undoing a newer approved release.

## 9. Owners and dependencies

Datarim engineer implements, separate reviewer examines exact head and full suite, release maintainer runs the tag/release workflow described in P5. Arcana-Brain provides architecture/source review, not a substitute for owner code authority. DEUS/DEVIL provide coordination and capability, never missing credentials or waiver. Scrutator engineering owns KB provenance/ACL/recall. Existing Muneral is task authority for Arcanada. Product repo branch, PR and green required checks are mandatory; who approves the merge is set by the approval policy (section 7a), which in Arcanada is blind agent review with no human gate. No marketing announcement or cross-project rollout until P4 acceptance.

## Sources and access limitations

- Datarim reviewed source: https://github.com/Arcanada-one/datarim/tree/8e738a4f583cb96904c41573ca5334dc148ec252
- Scrutator source: https://github.com/Arcanada-one/scrutator/tree/f62a61edcb291cec26af4347418a524fe3751326
- Lean: https://lean-lang.org/doc/reference/latest/
- Clojure state: https://clojure.org/about/state and https://clojure.org/reference/refs
- GitHub security: https://docs.github.com/en/actions/reference/security/secure-use
- Reusable workflow source pins: https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations
- Artifact provenance: https://docs.github.com/en/actions/concepts/security/artifact-attestations
- Statistical interpretation: https://pmc.ncbi.nlm.nih.gov/articles/PMC4877414/
- External artifact link supplied by operator (could not fetch): https://claude.ai/artifact/WhPxZu5gyK2Rcroeg6SdUY
