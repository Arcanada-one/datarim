---
name: structured-outputs-integration-gate
description: Demands schema-unit + wrapper-path tests when API-side structured-output validation is added on top of an existing post-processing pipeline.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Structured-Outputs Integration Gate

When a task migrates an LLM-response handling path from prompt-engineered JSON
extraction to API-side structured-output validation (any provider's
schema-bound parse helper), there is a recurring failure mode at the
contract boundary between the **new validator** and the **pre-existing
post-processing filters** that historically cleaned the response.

The new validator usually runs against the parsed model object before the
old filters get a chance to silently strip non-compliant content. If the
legacy contract was «silently remove these tokens», the new validator
flips that to «hard-fail the whole response on first match» — a behaviour
regression that schema-unit tests cannot catch in isolation.

## Trigger

Load this skill when the task description, PRD, or plan mentions any of:

- Adopting an API's structured-output / JSON-schema / typed-parse endpoint.
- Replacing «return only valid JSON» prompt instructions with a schema-bound
  call.
- Adding a post-parse validation layer (output guard / contract-validator)
  alongside response-cleaning helpers that already exist.

## Test-plan contract

The test plan for the touched path MUST include both kinds of test —
neither alone is sufficient.

1. **Schema unit test.** Exercise the new schema in isolation: valid
   payload, invalid-shape payload, edge-of-range fields. Mocks the
   provider call. Locks the schema contract.
2. **Wrapper-path test.** Exercise the FULL handler from the path entry
   point through every existing post-processing filter AND the new
   validator. Inject a payload that the legacy filters would have
   silently cleaned. Assert the historical behaviour is preserved
   (silent strip + success) — NOT the schema-unit behaviour (hard reject).

The wrapper-path test is the gate. It is the only place the contract
between «new strict validator» and «old silent filter» is observable.

## Anti-patterns to refuse

- Schema-unit tests alone, even if exhaustive.
- Wrapper-path test that does not inject a payload the legacy filter
  was designed to strip.
- A validator that fires before the legacy filter runs (re-order or
  split the validator into a schema-only check + a post-filter
  «no-residual» safety-net helper).

## When the gate fires

If the task plan does not list both kinds of test, return to plan
generation and add them before any implementation. If implementation
is already underway, do not merge until the wrapper-path test is
green AND deliberately attempts the legacy strip scenario.

## Why

A silent contract regression of this exact shape historically shipped
to a feature branch, passed schema-unit review, and was caught only
at human MR review by a maintainer who held the legacy filter contract
in memory. The schema tests were green; the production behaviour was
broken. One wrapper-path test would have closed the gap before review.
