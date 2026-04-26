# Third-Party Integration Checklist — {TASK-ID}

> Use for any task that adds, replaces, or significantly modifies an integration with an external HTTP API, SDK, webhook target, OAuth provider, payment gateway, message queue, storage API, LLM/STT/TTS endpoint, or anything else not under our control.
>
> Stack-neutral — fill in the language / HTTP client / test runner commands that match the project's stack (see project CLAUDE.md for canonical choices). Reference from `dr-plan` Step 6 (Technology Validation) when the task contains the `external API` keyword or introduces a new third-party dependency.

## 1. Endpoint Shape Verification (mandatory, before any code is written)

Per `$HOME/.claude/skills/research-workflow.md` § Empirical Provider Verification — documentation drifts, SDKs paper over differences, and "this worked elsewhere" memories are not evidence. Confirm the contract against the live endpoint.

```
1. Send the smallest valid request that exercises the *real* input shape (curl / httpx / fetch / equivalent).
2. Capture the success response → datarim/tasks/{TASK-ID}-fixtures.md
3. Capture an error response (bad auth / malformed payload / oversized input) → same fixture file.
4. Diff the captured shape against the plan's assumptions (field names, content-type, modalities, required flags such as `stream`, `response_format`, `modalities`).
```

**Trigger to revise the plan**: any field name, content-type, status code, or required flag in the captured response differs from the plan's assumption. Fix the plan before writing code.

| Probe | Endpoint | Auth method | Captured at | Result |
|---|---|---|---|---|
| Success | | | | shape matches plan / **plan needs revision** |
| Error (auth) | | | | status code: ___ ; error encoded in: header / JSON / both |
| Error (payload) | | | | |

## 2. Auth Flow Trace

Document the full auth path the production code will use. One-line is fine; be explicit about token sourcing and rotation.

- Credential source (env var / vault path / OAuth refresh / signed JWT): ___
- Header / query / body shape (`Authorization: Bearer ...` / `X-API-Key: ...` / signed param): ___
- Token lifetime + rotation strategy: ___
- Failure mode if credential is invalid (HTTP status, response body, exception type): ___
- Local dev vs staging vs production credential isolation: ___

## 3. Format Compatibility Test

Send a **real** input through the integration end-to-end before claiming the path works. Synthetic placeholders (empty file, "hello world" string, mock JSON) are not sufficient — real production payloads expose encoding edge cases that synthetic ones hide.

| Input class | Real sample tested? | Result | Notes |
|---|---|---|---|
| Smallest valid input | yes / no | | |
| Largest expected input (at the documented limit) | yes / no | | |
| Realistic production payload | yes / no | | |
| Locale / encoding edge case (UTF-8 multi-byte, RTL, emoji, large numbers) | yes / no / N/A | | |

## 4. Cost & Quota Review

| Tier | Limit | Our expected volume | Headroom |
|---|---|---|---|
| Free / cheapest | requests/day, tokens, MB transferred | | |
| Paid | next-tier ceiling and price | | |

- Where is the live usage dashboard? URL: ___
- Who owns the billing alert? Person / channel: ___
- Soft / hard limits on rate (RPS, RPM, TPM, concurrent requests): ___
- Behaviour when the limit is exceeded (429? 503? hard failure?): ___

## 5. Failure-Mode Mapping

| HTTP / error | Cause | Provider behaviour | Our handling |
|---|---|---|---|
| 401 / 403 | bad / expired credential | | retry-with-rotation / surface to user / abort |
| 429 | rate-limit | retry headers? Retry-After? | exponential backoff / queue / drop |
| 4xx (validation) | malformed payload | error in body or header? | surface / log / 400 to client |
| 5xx | provider outage | duration history? | retry / circuit-break / fallback to alternative |
| Timeout | network / cold start | typical p99 latency? | client timeout: ___ s |
| Errors-encoded-in-200 / 201 | provider returns 200/201 with error JSON | which fields signal error? | check before parsing |
| Idempotency / duplicate-detection | provider semantics on retry | idempotency key? | implement / N/A |

> **Common pitfall**: many APIs (Claude CLI, some streaming endpoints) return HTTP 200/201 even on errors, encoding the failure inside the JSON. Parsers that key off status code alone silently produce bad data. Capture an error-case fixture (Step 1) to verify which channel the provider actually uses.

## 6. Mock-vs-Real Toggle Plan

If the implementation includes a mock provider for tests / local dev / CI:

- How is the toggle controlled (`{PROVIDER}_PROVIDER=mock` env var / DI override / feature flag)? ___
- Is the real provider exercised in **at least one** automated test on CI? yes / no
  - If no — record a follow-up to add an integration smoke (the mock alone hid TRANS-0015's broken OpenRouter STT integration for months).
- Production default: mock / real ? ___
- Plan to retire the mock once the real provider is stable for: 7 days / 30 days / N/A.

## 7. Observability Hooks

| Signal | Captured? | Where |
|---|---|---|
| Request count + per-status breakdown | yes / no | logs / metrics / dashboard URL |
| p50/p95/p99 latency | yes / no | |
| Error-rate alert (paging threshold) | yes / no | |
| Quota / spend alert | yes / no | |
| Audit log of every call (when required by compliance) | yes / no | |

## 8. Rollback / Provider-Swap Strategy

- If this provider goes down for > N minutes, what's the fallback? Alternative provider / queue + retry / hard fail / N/A.
- How is the swap triggered (env var flip / feature flag / config reload)?
- How quickly can it be executed (minutes)?
- Is the alternative provider tested **at least monthly** so the rollback path stays warm? yes / no.

## Validation Checklist (before promoting plan to `/dr-do`)

```
[ ] Real endpoint probe captured into datarim/tasks/{TASK-ID}-fixtures.md (success + error)
[ ] Plan's assumed response shape matches captured shape (or plan was revised)
[ ] Auth flow documented end-to-end including failure modes
[ ] Real-data format compatibility test passed (not synthetic)
[ ] Cost / quota headroom verified against expected production volume
[ ] Failure-mode table filled in for 401 / 429 / 4xx / 5xx / timeout / errors-encoded-in-2xx
[ ] If a mock provider exists: the real provider is exercised in at least one CI test
[ ] Observability + alert hooks are scoped (or follow-up backlog item is open)
[ ] Rollback / provider-swap path is documented and (where feasible) tested
```

## Source

TRANS-0015 — voice transcription integration spent ~30 minutes generating 8 unit tests + integration code for the wrong OpenRouter model paradigm because the existing integration was trusted without empirical verification. A 3-minute curl test would have eliminated the false start. This template makes that probe a planning-time gate rather than a mid-implementation discovery.
