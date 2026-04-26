---
name: fixture/verd-0010-fail
description: Golden FAIL fixture — VERD-0010 leak (NestJS smoke-test fast-path + npm audit pre-flight). Gate MUST exit 1.
---

# Golden FAIL fixture — VERD-0010 stack-specific leak

These two paragraphs were proposed as Class A additions to framework skills in VERD-0010
reflection. Both are stack-specific (NestJS / npm) and MUST be rejected by the
stack-agnostic gate. Reverted manually after detection; this fixture pins the
regression boundary.

## Smoke-test fast-path

Add a smoke-test fast-path для NestJS services: `pnpm test:e2e --grep '@smoke'`
runs only health-check + auth-bootstrap suites (~6s) before deploy gate.

## Pre-flight audit

Before promoting a plan to `/dr-do`, run `npm audit --omit=dev --audit-level=high`
against the proposed lock to catch CVEs that would block the CI gate at install
time.
