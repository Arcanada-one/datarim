# TUNE-0584 · Make "unconfigured" distinguishable from "on-host" without breaking the exit-code contract

**Date:** 2026-08-16
**Status:** done
**Complexity:** L2
**Follows:** the "Left open" item recorded in `archive-TUNE-0583.md`

## The defect

`eh_decision` returns `0` for two different facts:

| Reality | Exit code |
|---|---|
| This host IS the declared execution host | `0` |
| This workspace has no execution mandate at all | `0` |
| This host is NOT the declared one | `10` |

The first two are indistinguishable. A guard that was never installed produces
exactly the same observable result as a guard that ran and passed: **silence**.
So a machine with no protection whatsoever reads as healthy.

This is not theoretical. It is how a real outage stayed invisible on one host
while a second host, mis-wired in the opposite direction, denied every task on
its own declared `required_host`. A control wrong in both directions at once,
and neither direction was visible from the exit code.

## Why the obvious fix is wrong

The tempting change — mint a new exit code for *unconfigured* — breaks every
consumer. Verified against the actual consumer before designing: the site's
PreToolUse guard dispatches on

```bash
case "$verdict" in
    0)  exit 0 ;;      # allow
    3)  ... deny ... ;;
    *)  ... deny ... ;;   # <-- a new code lands HERE
esac
```

A new code falls into `*)`, so **every unconfigured workspace in the world would
start denying**. Eleven shipped command docs branch on `0 == proceed` the same
way. `0` means "proceed" and must keep meaning exactly that.

## The fix: an out-of-band channel, not a new code

`eh_decision` and `eh_decision_intent` now set `EH_STATE` in the **caller's**
shell (they are functions, not subshells) before returning:

`on-host` | `unconfigured` | `off-host` | `fail-closed` | `readonly-bypass`

Exit codes are byte-for-byte unchanged. A consumer that ignores `EH_STATE`
behaves identically to before; one that reads it can finally tell the two
meanings of `0` apart.

Two deliberate decisions:

- **Not exported.** An exported copy would go stale in subshells while still
  looking authoritative — reintroducing false-confidence in a new place.
- **`readonly-bypass`, not `on-host`.** Read-only intent short-circuits *before
  any host resolution happens*. Labelling that "on-host" would be the same
  false-health claim this whole change exists to remove.

## The control that makes it real

A variable nobody reads changes nothing, so `dev-tools/check-execution-host-health.sh`
answers "is this machine actually gated?" by running the resolver twice:

- **POSITIVE** control — as the real current host: must resolve `on-host`.
- **NEGATIVE** control — under a hostname that cannot match: must resolve `off-host`.

Both must hold. *A control that has never been observed denying has not been
observed at all.* It reports `UNCONFIGURED` out loud rather than passing
quietly, and fails closed (exit 2) on a missing library or unresolvable root —
an environment error must never read as health.

## Verification

- **Existing contract intact:** all 35 pre-existing `execution-host.bats` tests
  pass untouched. That is the load-bearing evidence that no consumer breaks.
- **New coverage:** +9 `EH_STATE` tests (44 total), the first asserting the exact
  conflation — `on-host` and `unconfigured` both exit `0` yet report different
  states — plus caller-shell visibility and the not-exported guarantee.
- **Mutation controls (the important ones):** `check-execution-host-health.bats`
  seeds a resolver whose negative control does NOT deny, and asserts the health
  check goes **red**. A health check that cannot fail is precisely the defect it
  exists to detect, so it is tested for its ability to fail, not only to pass.
- **Live on all three fleet hosts**, both controls each:

  | Host | positive | negative | verdict |
  |---|---|---|---|
  | control machine | `off-host` | `off-host` | correctly off-host |
  | execution host A | `on-host` | `off-host` | gated |
  | execution host B | `on-host` | `off-host` | gated |

- **Found a real environment fact while probing:** on execution host A the same
  machine answers `UNCONFIGURED` for a privileged shell (whose `$HOME` cannot see
  the user-local routing map) and `on-host` for the owning user. Previously both
  were silent `0`. The tool now reports each honestly — which is the entire point.
- `shellcheck -S warning` clean. The two `SC2034` suppressions are scoped to the
  exact assignments (never file-wide, which would mask genuinely unused variables
  added later) and justified inline: `EH_STATE` is read by callers, not here.

## Notes

`documentation/how-to/fleet-hook-sync.md` and § S10-bis now tell hook authors to
assert `EH_STATE=on-host` rather than `rc=0`, and to prove a deny under a foreign
hostname. Enforcement remains site policy — this change ships mechanism only,
consistent with the preceding decision.
