# TUNE-0583 · Stop shipping the execution-host guard — mechanism ships, policy does not

**Date:** 2026-08-16
**Status:** done
**Complexity:** L2
**Decision method:** four-agent consilium (security · SRE · architect · strategist), unanimous

## The question

A PreToolUse guard (`datarim-exec-guard.sh`) existed in **two** repos at once: this public
framework and a private consumer workspace. Where should it live?

## Root cause — and why "just update the shipped copy" was rejected

The tempting fix was to copy the good version over the stale one. The architect's framing killed it:

> The root cause is not "the shipped copy was stale". Staleness is the symptom. It is **two writable
> copies of one executable artefact with no sync mechanism and no ownership arrow** — a DRY violation
> on an *enforcement* artefact, the worst class, because divergence fails closed.

Falsifiable test applied: after that fix, would any CI check fail when the two files diverge? No, and
none was proposed. So it re-arms the identical failure at the next edit to either copy.

**The drift was wrong in both directions at once**, which is what made it hard to see:

| Host | Symptom |
|---|---|
| execution host A | guard **denied every task ON ITS OWN declared `required_host`** — the resolver there answered correctly (`eh_decision` → 0, on-host); the stale guard never consulted it |
| execution host B | **no protection at all** — no map, hook unregistered, symlink into a framework clone |

## The line the panel drew: mechanism vs policy

| Piece | Verdict | Why |
|---|---|---|
| `lib/execution-host.sh` (resolver) | **ships** | answers "which host is declared" — pure mechanism |
| `check-execution-host-drift.sh` | **ships** | reports declaration-vs-reality; diagnostic |
| `tests/execution-host.bats` | **ships** | tests the shipped resolver |
| `session-execution-drift-warn.sh` | **ships** | advisory, degrades safely |
| `datarim-exec-guard.sh` | **removed** | encodes *policy* — that work on a non-declared host is forbidden. True only under one site's control-node/execution-host topology. For a single-machine user the hook **can only ever deny**. |

Precedent: `datarim-dispatch.sh` — same topology, already removed.

## What the panel added that a single reading would have missed

- **Security:** no secret or topology leak — no IPs, hostnames or private paths in either copy; those
  live only in the gitignored map and `space.yml`. The disclosure is of internal control-plane
  *design*, low severity. Explicitly **not** the reason to remove it — "anyone claiming *leak* is
  inflating". The real argument is that a control wrong in both directions is worse than none.
- **SRE:** hard precondition — do not ship the removal and the delivery path in separate cycles, or
  Incident 1 (loud, host-scoped) becomes Incident 2 (silent, fleet-wide). Also identified the trap:
  **`eh_decision` returns 0 for both *on-host* and *unconfigured***, so a fail-open no-op is
  indistinguishable from a healthy pass. Verified in source before acting.
- **Strategist:** a stranger cloning the repo hits a documented file that does not exist
  (`datarim-dispatch.sh`), then either wastes an hour on an inert hook or bricks every `/dr-*` with a
  partly-Russian error they cannot read. "That user does not file an issue; they delete the clone."

## Changes

**Removed:** `dev-tools/datarim-exec-guard.sh`, `dev-tools/tests/datarim-exec-guard.bats` — the tests
follow their subject. Both moved to the consumer workspace, where all 28 guard tests still pass.

**Added:** `dev-tools/check-class-b-not-shipped.sh` — ship-time gate, so the rule stops being prose.
TUNE-0500 already declared this script class-b; TUNE-0519 shipped it anyway. *A rule with no
enforcement is not a control.* The denylist is explicit rather than pattern-based: a heuristic like
"anything named `*-guard.sh`" would misfire on `branch-integration-guard.sh`, which is genuinely
framework-generic.

**Docs (7 surfaces):** every "The framework ships the PreToolUse guard… install it as a hook" replaced
with a capability statement. Two references to the absent `datarim-dispatch.sh` removed.
`documentation/how-to/fleet-hook-sync.md` told operators to symlink the guard **out of the framework
runtime** — the precise instruction that caused the original defect — now corrected to link from the
site's own repo. `CLAUDE.md` § S10-bis rewritten, and now carries the exit-code warning so anyone
writing their own hook does not inherit the same blind spot.

**Side benefit:** 13 lines of Russian left the public surface with the guard, satisfying the
English-only shipped-surface rule. Real, but a policy violation — not a security finding.

## Verification

- Class-b gate: **red on the real violation → green after removal**, plus a seeded positive control
  (reintroduce a class-b file in a scratch tree → exit 1). A gate that has never gone red proves
  nothing.
- `tests/exec-guard-wiring.bats` **rewritten, 14/14** — assertions deliberately inverted: the guard
  MUST be absent, the docs MUST NOT promise it, the mechanism MUST remain.
- Architect's falsifiable acceptance: `rg -n 'ships the PreToolUse guard' commands/` → **0**.
- SRE precondition met on all three fleet hosts: each passes positive **and** negative control
  (`EH_TEST_HOSTNAME=foreign` → deny), and **none** resolves its guard through a framework clone any
  more.
- **Simulated the feared regression**: deleted the framework's guard copy on the host that used to
  depend on it — protection survived, both controls still correct.

## Left open

`eh_decision`'s conflation of *on-host* and *unconfigured* under exit 0 is now documented but not
fixed. Splitting it is a behaviour change to a shipped library with its own 35-test suite and belongs
in its own task, not here.
