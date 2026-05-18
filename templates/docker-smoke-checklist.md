# Docker Smoke-Test Checklist

A reusable 5-step checklist for verifying a change inside Docker before declaring DoD-complete. Use for any task
that orchestrates external shell scripts, performs cross-container I/O, or relies on environment-specific
behavior (TLS, DNS aliases, file permissions, mounted configs).

Reference: `$HOME/.claude/skills/testing.md` § Live Docker Smoke Test Before Archive.

---

## Step 1 — Compose Validity

```bash
# noshellcheck-extract
cd "$REPO_DIR/_docker" && docker compose config --quiet && echo VALID || echo INVALID
```

**PASS**: `VALID` printed. **FAIL**: any YAML parse / schema error.

---

## Step 2 — Container Health

```bash
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

For every container the change touched:
- `Up` (preferred)
- `Up (healthy)` if a healthcheck is defined
- `Up (unhealthy)` is acceptable **only if pre-existing** — confirm by checking the same container status before
  the change. Document any pre-existing unhealthy state in the report; do not introduce new ones.

**PASS**: no new unhealthy containers. **FAIL**: a container that was healthy before is now unhealthy / restarting.

---

## Step 3 — API / Service Endpoint Smoke

For each external surface the change exposes:

```bash
# Frontend (via reverse proxy)
curl -s -o /dev/null -w "HTTP %{http_code}\n" -H "Host: <vhost>" "http://localhost:80/"

# Direct API
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://localhost:<api-port>/<health-endpoint>"

# Authenticated endpoint
TOKEN=$(curl -s ".../auth/sign-in-dev?email=..." | jq -r .accessToken)
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:<api-port>/<endpoint>"
```

**PASS**: HTTP 200 (or expected non-2xx for negative cases). **FAIL**: 5xx, connection refused, timeout.

---

## Step 4 — End-to-End Action Smoke

The actual thing the task enables. Examples by task type:

- **Database change**: insert a row → query it back → check expected columns/types.
- **Background job**: trigger it → check job_state / queue table → verify final state.
- **Cross-container call** (backend service → static-fileserver → bash → DB): run the full chain via the real entry point
  (`docker exec <api> sh -c "..."` or `curl <api-url>`), then verify **post-conditions**:
  - Target files exist with expected count (not just "directory created")
  - Target DB exists with expected schema
  - Target table row count matches source (or expected delta)
  - Job_state row reports success **and** post-condition checks confirm it
- **File I/O**: file count + size + content checksum on a sampled subset.
- **Configuration change**: process restarted, new config loaded, behavior reflects new setting.

**Critical**: do not trust the parent's `success:1` flag. Legacy Yii/PHP/bash chains often report success when
the script ran but produced no output. Verify post-conditions independently.

**PASS**: all post-conditions match expectations. **FAIL**: any post-condition off, even if exit code was 0.

---

## Step 5 — Rollback Verification

```bash
# nosec-extract
# Dry-run revert in a scratch worktree to confirm it would apply cleanly
git revert --no-commit <commit-sha> && git revert --abort
```

For Docker config changes: confirm `docker compose up -d --force-recreate <service>` brings affected services
back to pre-change state.

**PASS**: revert applies cleanly, services recoverable. **FAIL**: merge conflict on revert, or a service won't
restart on prior config.

---

## Reporting Template

Append to QA / compliance report:

```markdown
### Docker Smoke Test

| Step | Status | Evidence |
|------|--------|----------|
| 1. Compose Validity | PASS | `docker compose config --quiet` → VALID |
| 2. Container Health | PASS | All Up; pre-existing unhealthy: <list or "none"> |
| 3. Endpoint Smoke | PASS | UI 200, API 200, authenticated GET 200 |
| 4. End-to-End Action | PASS | Source 683 posts → target 683 posts; DB exists; job_state status=2 |
| 5. Rollback Verification | PASS | `git revert --no-commit` clean; force-recreate restores prior state |

**Overall**: PASS — safe to mark DoD complete.
```

---

## Anti-Patterns to Refuse

If during your smoke test you needed any of the following to make it work, **do not** mark the task complete.
The hack belongs in the committed configuration, not in the session:

- `docker exec <c> sh -c "chmod +x ..."` — fix exec bit in git: `git update-index --chmod=+x <file>`
- `docker exec <c> sh -c "echo '<ip> <name>' >> /etc/hosts"` — add to `extra_hosts` in compose
- `docker exec <c> sh -c "echo '...' > /root/.my.cnf"` — add as a volume-mounted file in compose
- `--ssl=0` / `--skip-ssl` flags on the CLI — add to `[client]` in a mounted `.my.cnf`
- Recreating a container repeatedly until a race condition resolves — diagnose the race instead

Reference pattern: a cross-container clone chain hid three runtime bugs behind hundreds of passing unit tests
because no one had ever run the chain end-to-end in Docker. The fix lived entirely in `docker-compose.yml` +
a new `.my.cnf` + a single git exec-bit, not in any application code.