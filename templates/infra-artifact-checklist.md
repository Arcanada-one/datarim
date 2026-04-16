# Infrastructure Artifact Checklist

**Task:** {TASK-ID}
**Type:** Infrastructure
**Pattern:** Local artifacts → Commit → Checkpoint → Operator remote execution

---

## Phase A: Local Artifacts (agent-safe)

- [ ] All configs created (Docker Compose, HCL, YAML, JSON, etc.)
- [ ] All scripts created and `chmod +x` (provision, bootstrap, migrate)
- [ ] All scripts pass `bash -n` syntax check
- [ ] All JSON/YAML pass format validation (`jq empty`, `yq eval`)
- [ ] Runbook documentation written (bootstrap, unseal/start, daily ops, DR)
- [ ] Operator guide written (quick start, daily ops, rollback)
- [ ] No hardcoded secrets in any artifact (grep for patterns)
- [ ] `.env` and credential files → `chmod 600` in scripts
- [ ] Pre-commit hook includes secret-scan patterns (if new to repo)
- [ ] Git commit created (reversible via `git revert`)

**Checkpoint:** Present summary to operator. Confirm which remote phases to proceed with.

## Phase B: Remote Execution (operator-gated)

### Secret initialization (if applicable)

⚠ **Law 1 fence:** Operations that generate secrets (Vault init, SSH keygen, token creation) MUST:

- Run ONLY interactively on the target host (never in background/CI/conversation)
- Output collected by operator IMMEDIATELY (Shamir keys, root tokens, private keys)
- Output `shred`-ed / `clear`-ed after collection
- Never appear in agent conversation logs, CI output, or git history

### Per-phase execution

For each phase:
- [ ] Run on target host
- [ ] Verify success (check command in runbook)
- [ ] Update documentation with live values (IPs, hostnames, counts)
- [ ] Commit doc updates

### Validation

- [ ] Idempotency test: re-run provision → no-op
- [ ] Rollback test: delete + re-provision → working state in ≤15 min
- [ ] Smoke test: primary use case works end-to-end
- [ ] Security test: unauthorized access denied (port scans, policy checks)

## Phase C: Post-execution

- [ ] Second QA pass (`qa-report-{TASK-ID}-remote.md`)
- [ ] Second compliance pass (`compliance-report-{TASK-ID}-remote.md`)
- [ ] Reflection update with deployment learnings
- [ ] Archive