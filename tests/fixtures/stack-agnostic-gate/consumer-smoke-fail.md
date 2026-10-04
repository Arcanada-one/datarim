---
name: fixture/consumer-smoke-fail
description: Golden FAIL fixture — stack-specific smoke and audit instructions. Gate MUST exit 1.
---

# Golden FAIL fixture — stack-specific smoke and audit instructions

These two negative examples are stack-specific (NestJS / npm) and MUST be
rejected by the stack-agnostic gate. The fixture pins the regression boundary
without identifying the consumer incidents that motivated it.

## Smoke-test fast-path

Add a smoke-test fast-path для NestJS services: `pnpm test:e2e --grep '@smoke'`
runs only health-check + auth-bootstrap suites (~6s) before deploy gate.

## Pre-flight audit

Before promoting a plan to `/dr-do`, run `npm audit --omit=dev --audit-level=high`
against the proposed lock to catch CVEs that would block the CI gate at install
time.
