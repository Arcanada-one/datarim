---
name: v-ac-feasibility
description: Pre-implementation gate proving every runtime-command V-AC (docker exec / curl / kubectl / systemctl / live DB query) can actually PASS before /dr-do.
metadata:
  current_aal: 1
  target_aal: 2
---

# V-AC Feasibility — Verifiable Acceptance Criteria Feasibility Gate

**Role**: Planner / Reviewer Agent (invoked from `/dr-plan` during the V-AC ↔ AC review — Step 5c spec-graph validation and the Step 6.5 audit bullets).

## When this skill is active

Arm this gate when the plan's Validation Checklist contains **any V-AC whose
verification is a runtime command** — a command that reads live process,
container, or service state rather than static files. Trigger surfaces:

- `docker exec <container> <cmd>` / `kubectl exec <pod> <cmd>`
- `curl` / `wget` / HTTPie / Playwright `page.goto` against a running service
- `systemctl` / `journalctl` state or log assertions
- `redis-cli` / `psql` / `mongosh` live-query assertions
- any assertion over the value of a *running* process's environment, memory,
  or in-flight state (as opposed to a file on disk).

A plan whose V-AC are all static (`test -f <path>`, `grep <pattern> <file>`,
lint/unit exit codes) does not need this gate — those are deterministic against
the working tree and cannot be «infeasible by runtime semantics».

## The failure this gate prevents

A V-AC can be **written, reviewed, and cite the correct AC number, yet be
impossible to satisfy under any correct implementation** — because the runtime
command tests something the runtime semantics never expose.

Motivating incident: an AC asserting «env var X is set to Y on the running
service» was verified by `docker exec <container> printenv X`. But
`printenv` reads the *shell's* environment, not the value a running Node
process holds after `process.env[X] = Y` was set in code. The assertion could
never pass, no matter how correct the implementation — yet it survived the plan
review because the reviewer matched the AC number and the command *shape*
without executing the command against a real (or skeleton) runtime.

The lesson: **verbatim AC↔V-AC mirror and semantic-match review are necessary
but not sufficient.** A V-AC must also be *feasible* — a correct implementation
must be able to make it PASS. Feasibility is a property of runtime semantics,
not of text, and text review cannot detect it.

## The contract: prove feasibility, don't assume it

For every runtime-command V-AC, the plan MUST demonstrate — before locking the
V-AC into the Validation Checklist — that the command *can* return the PASS
result when the implementation is correct. Acceptable evidence, in order of
preference:

1. **Dry-run against a real runtime.** Execute the command against the running
   dev / staging / test service (or a stubbed skeleton that stands in for the
   final one) and confirm it produces an observable, correct result under a
   *deliberately-correct* fixture. Quote the result inline in the plan.
2. **Semantic proof of the observation path.** When no runtime is reachable at
   plan time, the plan MUST name the exact mechanism through which the asserted
   value becomes observable to the command — e.g. «the value is logged via the
   application logger and asserted with `journalctl -u <unit> | grep`», or «the
   value is exposed on `/healthz` JSON and asserted with `curl … | jq`». A
   command whose observation path cannot be named is presumed infeasible.
3. **Re-scope to a feasible assertion.** If neither (1) nor (2) holds, replace
   the V-AC with one that *is* observable — assert the log line, the HTTP
   response field, or the persisted side-effect instead of the in-process
   value the runtime never exposes.

## Common infeasible patterns (re-scope, do not ship)

| Infeasible V-AC | Why it can never PASS | Feasible replacement |
|---|---|---|
| `docker exec C printenv X` for a value set via `process.env[X]=Y` in code | `printenv` reads the shell env, not the live process's mutated env | Assert the app log line / a `/config` health field that echoes X |
| `curl <url>` before the service binds the port / route exists | route unmapped ⇒ 404 regardless of correctness (see `/dr-plan` routing-convention probe) | grep the router for the real path first; assert the mapped route |
| `kubectl exec … cat /proc/1/environ` for a runtime-mutated var | `/proc/1/environ` is the launch env, frozen at exec time | Expose the value through an app endpoint or structured log |
| `systemctl show -p Environment` for an app-set variable | shows unit-declared env, not values set inside the process | Assert via the app's own observability surface |

## Output

Record the feasibility verdict inline in the plan next to each runtime-command
V-AC, so a reviewer replays it without re-querying:

- `V-AC-N — feasible (dry-run: <command> → <observed PASS result>)`, or
- `V-AC-N — feasible (observation path: <named mechanism>)`, or
- `V-AC-N — infeasible as written → re-scoped to <new assertion>`.

A runtime-command V-AC with no feasibility annotation is a planning defect:
fix the plan (prove or re-scope) before transitioning to `/dr-do`. Catching an
infeasible V-AC at plan time costs one dry-run or one grep; catching it at
`/dr-do` or `/dr-verify` costs a full pipeline cycle plus a V-gate reformulation.
