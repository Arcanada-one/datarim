---
name: testing/concurrency-patterns
description: Concurrency verification for provider fan-out and shared-resource custody: overlap, cleanup, and owner progress.
---

# Testing — Concurrency Patterns

## Resource custody: safety and progress

When repairing concurrent resource acquisition, test both custody safety and
owner progress. A registry mutex that prevents a descriptor from escaping can
also prevent its current owner from releasing the contested resource if the
waiter holds that mutex during a blocking acquisition.

Use a real owner and contender: establish ownership, synchronize the contender
at the actual contention point, then release the owner while the contender is
still waiting. Assert that release completes and the contender acquires before
its deadline. A timeout-only rejection test does not exercise this release path.
Also retain the original allocation/registration, failure-cleanup and child
inheritance regressions; a liveness repair must not reopen the safety race.

Keep synchronization around the smallest custody transaction that closes the
race, and inspect whether any awaited operation requires another thread to take
the same mutex to make progress. Test supported interleavings with barriers and
bounded deadlines, not arbitrary sleeps or a single uncontended happy path.
Document unsupported reentrant callbacks explicitly instead of implying that a
concurrent-thread test proves them. This recipe applies to resource-lifecycle
changes; it does not require concurrency tests for unrelated single-owner code.

## Provider Race (bounded fan-out, first-success short-circuit)

Use this pattern whenever an agent, daemon, or service fans a single request
out over **multiple interchangeable endpoints** (LLM providers, model
fallback chains, mirror APIs, redundant upstreams) and any one successful
response is sufficient.

### Pattern components (all five are load-bearing)

1. **Bounded worker pool.** Submit one attempt per endpoint to a pool whose
   size is capped at the number of endpoints (or lower). Unbounded spawning
   turns a provider outage into a resource leak.
2. **Completion-ordered iteration.** Consume results in the order attempts
   *finish*, not the order they were submitted. Submission-ordered joining
   serializes on the slowest early entry and defeats the race.
3. **First-success short-circuit.** The first successful result wins: return
   it immediately and cancel (or abandon-with-cleanup) the still-running
   attempts. Losers' results are discarded, and their failures are recorded
   at debug level only.
4. **Alert only when ALL fail.** A single provider failing while another
   succeeds is normal operation, not an incident. Raise the operator-facing
   alert (and the loud error log) only when every endpoint in the fan-out
   has failed. Per-provider failures inside a won race are noise — alerting
   on them is the alert-fatigue anti-pattern this pattern exists to remove.
5. **Barrier-based concurrency test.** The regression test MUST prove the
   attempts actually overlap: give each fake provider a synchronization
   barrier sized to the expected parallelism and have every attempt wait on
   it before responding. If the implementation silently degrades to
   sequential calls, the barrier never releases and the test times out —
   a deterministic red, with no sleep-based flakiness.

### IMPORTANT caveat — join-all latency

If the call site waits for **all** workers to finish before returning
(a join-all / wait-for-pool-shutdown construct), the function returns at
the latency of the **slowest** attempt — one full per-endpoint timeout cap
in the worst case. The win of this pattern is **correctness and fewer
alerts** (no false incident when one provider is down), **NOT speed**. Do
not present or measure it as a latency optimization unless the losers are
genuinely cancelled before return.

### Budget sizing

Size the worst-case latency budget of the caller at **one** per-endpoint
timeout cap — the race runs the attempts concurrently, so the worst case is
the slowest single attempt, **not the sum** of all caps (that would be the
sequential-fallback budget). When reserving an upstream deadline or cron
slot for the racing call, reserve `max(per-endpoint caps) + small overhead`.

<!-- gate:example-only -->
```python
# Illustrative only (Python): bounded pool + completion order + short-circuit.
from concurrent.futures import ThreadPoolExecutor, as_completed

with ThreadPoolExecutor(max_workers=len(providers)) as pool:
    futures = {pool.submit(attempt, p): p for p in providers}
    errors = []
    for fut in as_completed(futures):
        try:
            return fut.result()          # first success wins
        except Exception as exc:         # loser failure -> debug, not alert
            errors.append((futures[fut], exc))
    alert_all_providers_failed(errors)   # only reached when ALL failed
```
<!-- /gate:example-only -->

Any language with a bounded task pool, completion-ordered result stream, and
a barrier primitive can express the same contract — the components above are
the portable specification; the fenced block is one concrete rendering.
