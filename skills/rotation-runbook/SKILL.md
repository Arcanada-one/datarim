---
name: rotation-runbook
description: Credential rotation playbook — consumer inventory, auth-scoped verification, full payload replay, canonical secret paths, rotation log.
current_aal: 1
target_aal: 2
---

# Rotation Runbook — Credential Rotation Playbook

A credential rotation looks trivial — issue a new secret, revoke the old one — and
that is exactly why it goes wrong. The recurring failure modes are not in the
rotation itself but around it: a consumer nobody remembered, a verification probe
that returns green without authenticating, a validation regression hiding behind
the auth failure, and a secret written back to a path no other document agrees on.
This skill formalizes the discipline distilled from repeated real rotation
exercises across the ecosystem (provenance: `documentation/how-to/evolution-log.md`).

## When To Use

Load this skill when the task involves:

- Rotating any credential: API key, access token, OAuth client secret, webhook
  signing secret, TLS key, database password.
- Responding to a leaked or exposed credential (accidental commit, plaintext file,
  audit finding).
- Verifying that a past rotation actually converged (secret store ↔ producer
  truth-check).

## The Runbook

### 1. Inventory every consumer BEFORE touching the credential

Enumerate every place the current credential is read: CI/CD secret stores, env
files on hosts, secret-manager paths, service configs, cron jobs, sibling
projects. A rotation that misses one consumer converts a working system into an
intermittently failing one, which is harder to debug than a clean outage.

Perform a **truth-check between the secret store and the producer**: the value the
consumer holds (e.g. a CI secret) and the value the issuing service considers
current can silently diverge — a prior rotation that updated one side only. Treat
"consumer copy ≠ producer truth" as the first hypothesis for any HTTP 401 from a
previously working integration.

### 2. Choose the rotation window deliberately

- **Grace window (dual validity)** — prefer it when the provider supports
  overlapping validity: issue new, roll consumers, then revoke old. Zero downtime.
- **Immediate revoke (grace = 0)** — required when the credential is actively
  leaked; acceptable otherwise only when all consumers can be updated atomically.
  Announce the expected blast radius before executing.

### 3. Verify with auth-scoped endpoints only

A verification probe MUST hit an endpoint that actually validates the credential.
Public or catalog endpoints return success without authentication and produce a
**false green** — the classic trap is verifying a revoked key against an endpoint
that never checked it. Required evidence, both directions:

- Old credential → authenticated endpoint → explicit rejection (401/403).
- New credential → same endpoint → success.

Allow for provider-side propagation delay (tens of seconds is normal) before
declaring a verification failed; re-probe once after a short wait.

### 4. Replay the FULL producer payload, not a minimal probe

An auth failure can mask a validation regression that accumulated while the
integration was broken. After rotating, replay the complete real payload the
producer sends end-to-end (the actual consumer call path, all required fields) —
not a minimal ping. A minimal probe proves the key works; only the full replay
proves the integration works.

### 5. Store the new secret at the canonical path

Write the new secret to the path defined by the project's canonical secret-store
schema document — never to a path invented at plan time. When plan-time convention
and the canonical schema disagree, pause and fix the plan; convention drift is
cheaper to correct before the secret lands than after three documents disagree
about where it lives. Secrets belong in the secret manager or
`${PROJECT_CREDS_DIR}` (gitignored) only — never in tracked files.

### 6. Record the rotation

Append a rotation-log entry to the project's credential document (under
`${PROJECT_CREDS_DIR}`): date, credential name, reason (scheduled / leak /
divergence), old-key rejection evidence, new-key success evidence, consumers
updated. The log is what turns the next "why is this 401ing" incident from
archaeology into a lookup.

### 7. Leak response — additional steps

When the rotation is triggered by an exposure:

- **Rotate first, scrub second.** The credential is compromised the moment it is
  exposed; history rewriting does not un-leak it.
- **Protect the pre-scrub backup.** A backup tag pushed to the same remote is
  destroyed by the subsequent `push --force --tags`; keep a local mirror clone as
  the canonical pre-scrub backup instead.
- **Verify the scrub from a fresh clone**, grepping all history for the leaked
  patterns — the working checkout that performed the scrub is not evidence.

## Failure-Mode Checklist

| Trap | Symptom | Countermeasure |
|------|---------|----------------|
| Consumer copy ≠ producer truth | 401 from a previously working integration | Step 1 truth-check |
| False-green verification | Revoked key still "works" | Step 3 auth-scoped endpoint |
| Hidden validation regression | 400 immediately after fixing the 401 | Step 4 full payload replay |
| Secret-path convention drift | Three documents name three paths | Step 5 canonical schema |
| Backup tag lost to force-push | Pre-scrub state unrecoverable on remote | Step 7 local mirror |
| Premature verification failure | New key rejected seconds after issue | Step 3 propagation wait |
