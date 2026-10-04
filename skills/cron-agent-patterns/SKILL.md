---
name: cron-agent-patterns
description: Layered timeout defense for cron-orchestrated agents calling external APIs (LLM CLI, HTTP, subprocess) — nested tiers, anti-patterns, headroom.
---

# Cron-Agent Patterns

> **TL;DR:** A cron-orchestrated agent that makes external API calls (LLM CLI,
> HTTP client, subprocess) can hang, drift past its window, or overlap the next
> cron tick. Defend with **nested timeouts** — each tier strictly smaller than
> the one enclosing it — plus symmetric deadline guards and explicit headroom
> for the next fallback tier.

## When To Apply

Load this skill when implementing or reviewing any agent that:

- runs on a schedule (cron, systemd timer, `sleep`-loop) **and**
- makes calls that can block indefinitely — LLM CLI subprocess, HTTP request,
  shell-out, DB query, or a provider fallback chain.

The pattern is **stack-agnostic** — the tier names below map onto any runtime
(Python `signal`/`subprocess`, Node timers/`AbortController`, Go `context`,
shell `timeout`).

## The Layered Timeout Ladder

Order the timeouts so each inner budget is strictly smaller than the budget
enclosing it. Violating the strict-nesting invariant means an inner tier can
never fire before the outer one preempts it — the inner guard becomes dead code.

```
(a) per-call timeout        <  (b) per-cycle deadline budget
                                     (wall-clock, time.monotonic)
(b) per-cycle deadline      <  (c) SIGALRM safety net
                                     (catches C-level blocked syscalls the
                                      library-level timeout cannot interrupt)
(c) SIGALRM safety net      <  (d) shell `timeout --kill-after` outermost guard
                                     (cron-level watchdog; kills the whole
                                      process tree if everything above wedges)
```

- **(a) Per-call timeout.** Bound every individual external call (HTTP read
  timeout, subprocess timeout, LLM CLI `--timeout`). Must be short enough that
  the whole cycle — including retries and fallbacks — still fits inside (b).
- **(b) Per-cycle deadline budget.** Compute a monotonic deadline once at
  cycle start (`deadline = time.monotonic() + CYCLE_BUDGET_SEC`). Before every
  external call, check `time.monotonic() < deadline`; skip the call if not.
- **(c) SIGALRM safety net.** A library-level timeout cannot interrupt a call
  blocked in a C-level syscall. Arm `SIGALRM` (or the runtime's equivalent
  hard alarm) so the process is forced back into your handler and raises a
  `CycleTimeout`.
- **(d) Shell outermost guard.** Wrap the whole invocation in
  `timeout --kill-after=<grace> <hard-limit> <cmd>`. This is the last line of
  defense when everything in-process has wedged. Set it above (c) so the
  in-process net gets first chance to exit cleanly.

## Anti-Patterns (each caused a real incident)

- **Per-call timeout == cycle budget.** If the per-call limit equals the whole
  cycle budget, the math forbids the call from ever fitting alongside retries
  or the next-tier fallback. A single slow call consumes the entire window.
- **`max(N, deadline - now)` floor.** Flooring a per-call timeout at a constant
  `N` re-inflates a doomed call after the deadline has already passed:
  once `deadline - now` goes negative, `max(1.0, deadline - now)` stages a
  fresh 1-second call *past* the deadline. Never floor the remaining budget —
  if `deadline - now <= 0`, skip the call, do not clamp it back up.
- **`except Exception: pass` swallowing the alarm.** A bare
  `except Exception:` around the call body silently eats the exception raised
  by the SIGALRM handler, so the safety net never propagates. **Re-raise**
  `CycleTimeout` (or the equivalent) *before* the generic handler:

  ```python
  try:
      result = call_provider(...)
  except CycleTimeout:
      raise                    # let the safety net escape
  except Exception:
      log_and_continue()       # only ordinary failures land here
  ```

## Required Guards

- **Symmetric deadline-passed guards in every fallback tier.** A fallback chain
  (primary → secondary → tertiary provider) must check the deadline *before
  each* tier, not only before the first. Otherwise the chain keeps trying new
  providers well past the cycle deadline.
- **Explicit headroom reservation for the next-tier fallback.** Reserve time so
  a fallback can still run after the primary times out. Subtract a named
  reserve constant (e.g. `MC_RESERVE_SEC`) from the budget handed to each tier:
  `tier_budget = (deadline - now) - RESERVE_SEC`. Without headroom the primary
  consumes the whole budget and the fallback is dead on arrival — producing
  duplicate timeout alerts with no recovery.

## Checklist

- [ ] Each timeout tier is strictly smaller than the tier enclosing it (a<b<c<d).
- [ ] Cycle deadline computed once with a monotonic clock at cycle start.
- [ ] Per-call timeout never floored back above the remaining budget.
- [ ] Deadline checked before **every** external call and **every** fallback tier.
- [ ] SIGALRM (or equivalent) armed for C-level blocked syscalls.
- [ ] `CycleTimeout` re-raised before any generic `except`.
- [ ] Explicit headroom reserved for the next fallback tier.
- [ ] Shell `timeout --kill-after` wraps the whole invocation as outermost guard.
