---
name: test-env-verification
description: Mandatory gate: verify the change on test env (backend + frontend) autonomously before prod prep or archive. Blocks /dr-qa, /dr-compliance, /dr-archive.
current_aal: 1
target_aal: 2
---

# Test-Environment Verification Gate

**Role**: Reviewer / Developer Agent (invoked from `/dr-qa` Layer 4, `/dr-compliance`, and `/dr-archive`).

## The rule (operator mandate)

When the project space has a **test environment**, a change MUST be verified on
that environment — **both backend and frontend** — *before* the task is prepared
for production deploy or archived. The verification is done **autonomously**: the
agent discovers the test environment, ships the change to it, exercises it, and
records the result, without asking the operator whether to test. Asking "did we
test on the test env?" each task is the failure mode this gate exists to remove.

This is distinct from (and runs alongside) the [[prod-readiness-probe]] gate:
- `prod-readiness-probe` checks **runner symmetry** (test↔prod sudoers/PATH/ports) — *can* prod accept the deploy.
- This gate checks **functional behaviour on the deployed test build** — *does the change actually work* once deployed, end-to-end, on a real environment.

Both must pass before prod prep / archive for a task that ships behaviour to a
project with a test environment.

## When this skill is active

Load and arm this gate when BOTH hold:

1. The change ships runtime behaviour (code, config, migration — not a docs-only
   or framework-only task).
2. The project space declares a test environment, OR one is discoverable. Resolution chain:
   - **Space registry (authoritative):** `spaces/<space>/space.yml` → `test_environments[]`
     (each entry: `name`, `kind: backend|frontend`, `url` or `host`, optional
     `deploy_branch`, `health_path`, `smoke` hint, `safe_mode` e.g. `dry_run`).
   - **CI heuristic (fallback):** a `deploy:test` / `deploy_*_test` job in the repo's
     CI gated on a branch push (commonly `dev`) whose `HEALTH_URL` / `environment.url`
     names a test host. Treat that host as the test environment.
   - **Neither found ⇒ verdict `NO-TEST-ENV`** — the gate is a no-op (record the
     finding so the operator can register one later). NO-TEST-ENV is NOT a pass of
     the verification; it is an explicit "no environment to test on".

A docs-only / framework-only / infra-inventory-only task ⇒ verdict **SKIP**.

## The contract: never prep-for-prod or archive on an unverified test environment

The framework MUST NOT recommend a production deploy, and MUST NOT archive the
task, until the change has been exercised on the test environment (or the gate
resolved SKIP / NO-TEST-ENV). The pipeline order is fixed:

```
implement → /dr-qa (incl. THIS gate) → /dr-compliance (re-assert) → test-env PASS
   → [operator-gated] prod deploy → /dr-archive
```

Archiving a behaviour-shipping task for a test-env-having project without a
PASS / SKIP / NO-TEST-ENV record from this gate is a hard block.

## Autonomous procedure

1. **Resolve** the test environment(s) via the chain above. Record which source resolved it.
2. **Ship the change to the test environment.** The canonical path is the project's
   own `deploy:test` CI job — integrate the change onto the branch that triggers it
   (commonly `dev`). When the feature branch was cut from `main` and `dev` is far
   ahead of `main`, integrate by **cherry-picking only the task's commits onto a
   throwaway worktree off `origin/dev`** and fast-forward pushing — never a blind
   feature→dev merge (it drags main-only history into dev). Poll CI until the
   `deploy:test` job is green (a push to a shared/deployed branch is not done until
   CI is green — see [[testing]] § live smoke).
3. **Exercise backend** on the deployed test host: health endpoint + at least one
   behaviour-bearing call that touches the changed path. Prefer a **safe-mode**
   run when the test env can mutate real external systems (e.g. `dry_run=true`,
   content-only GET, a read path) — never trigger a destructive / billable external
   action on test without explicit operator sign-off. Capture the request, HTTP
   status, and the load-bearing field of the response (or the service log proving
   the value reached the external boundary).
4. **Exercise frontend** on the deployed test host: load the affected page/flow and
   confirm the change renders/behaves. If the test environment disables the agent's
   auth path (e.g. dev sign-in returns 404 on test by design), record that as a
   blocked-by-environment finding and fall back to the deployed-bundle check (the
   built asset contains the change) + the component/live-render Playwright run from
   `/dr-qa` Layer 4f — do NOT silently skip the frontend.
5. **Record** everything in the QA report under `### Layer 4h — Test-Environment Verification`:
   the resolved environment + source, the CI deploy pipeline + job result, the exact
   backend/frontend commands, captured output, and the per-surface verdict.

## Verdict

| Verdict | Meaning | Effect |
|---------|---------|--------|
| **PASS** | Backend AND frontend exercised on the deployed test env, behaviour confirmed | Pipeline MAY propose prod prep / archive |
| **PASS_WITH_NOTES** | Verified, with a recorded environment limitation (e.g. authed FE Playwright blocked by test 404, covered by bundle-check + component Playwright; or a billable backend action deferred to operator) | MAY propose prod prep / archive, note carried |
| **SKIP** | Docs-only / framework-only / no runtime behaviour | No-op |
| **NO-TEST-ENV** | No test environment registered or discoverable | No-op for THIS task; record so the operator can register one |
| **FAIL** | Change not shipped to test, or exercised and broken | Hard block — MUST NOT propose prod / archive |

A FAIL routes back to `/dr-do` (broken behaviour) or to the deploy step (not
shipped to test). A NO-TEST-ENV / SKIP never blocks, but is recorded verbatim.

## /dr-auto mode (autonomous activation)

Under `DATARIM_AUTO_MODE=1`, this gate runs **without asking**. The decision
"should I test on the test env?" is pre-resolved to **yes** by this skill — it is
never an `AskUserQuestion`. The only operator escalations permitted here are the
hard-gated boundary actions from [[autonomous-mode]] § Hard-gated Action Boundary
(a production deploy, or a billable/destructive external action on the test env
that has no safe-mode equivalent). Everything else — integrate to `dev`, poll CI,
run safe backend + frontend smoke — proceeds autonomously and is logged.

## Reference incident

A multi-repo feature once reached COMPLIANT with green
component/Playwright tests, but had **never** been merged to `dev` nor deployed to
the test environment — every prior "test" ran in isolated worktrees / throwaway
containers. The operator caught it at archive time and mandated this gate:
"always, if a test environment exists in the project space, test backend AND
frontend on it first — autonomously — before preparing the task for prod and
archive." On compliance the feature was integrated to `dev` in all 3 repos
(cherry-pick-onto-dev), all `deploy:test` jobs went green, and the backend was
verified end-to-end on the deployed test env (budget 40 → 40 000 000 micros at the
Google Ads boundary under `dry_run`; out-of-range budgets rejected 400).
