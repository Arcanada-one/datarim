# Atomic Cutover Runbook Template

Stack-neutral pattern for any live-service config flip, mount-point migration, or routing change where you need:

- a single transaction (no partial-state-left-live failure mode);
- pre-conditions enforced in code (refuses to run if invariants fail);
- a smoke-test pair that gates auto-rollback;
- byte-level traceability of what changed.

Use during `/dr-plan` or `/dr-do` for tasks that touch a live request path. Reference: `skills/security.md` § Cross-Stack Relative-Path Includes (companion threat-model recipe).

---

## When to use

- Flipping the active config of a long-running request handler (web server, reverse proxy, ingress controller, API gateway).
- Migrating mount points / volumes used by a running service.
- Replacing a routing source (whitelist file, map block, ACL list, feature-flag store) where the new and old behaviours overlap by design.

## When NOT to use

- One-shot batch jobs (no live request stream → smoke pair is meaningless).
- Read-only audits (no state mutation → no rollback needed).
- Schema migrations that change persistent storage (use a migration tool with its own transactional semantics).

---

## The 8-Phase Pattern

### Phase 0 — Pre-condition check (refuse if missing)

Encode invariants the cutover assumes (target inode tree present, downstream service alive, dependent symlink in place, lockfile not stale). Exit non-zero with a clear message if any invariant fails. Do NOT proceed with destructive ops on assumed state.

### Phase 1 — Pre-cutover smoke baseline

Capture full response shape per pilot host:
- response code
- content-type
- size
- redirect target (if any)

Write the result to a temp file. **Tuple comparison is the cheapest way to harden auto-rollback against false-PASS** (see `skills/ai-quality/bash-pitfalls.md` § Trap 6).

### Phase 2 — Backup the active artefact

Timestamped copy (`<artefact>.PRE-CUTOVER.<TS>`). Verify the backup is byte-identical to the source before continuing. Backup path goes into the rollback hook of every later phase.

### Phase 3 — Swap (atomic if filesystem supports it)

Move the new artefact into the active path. Prefer atomic operations (`rename(2)`, `cp -a` followed by `mv`, etc.). Avoid leaving a half-written state visible to the live service.

### Phase 4 — Validate the new config without taking traffic

Use the service's own validator (`<service> --check-config`, dry-run mode, lint command). On failure: invoke the rollback hook IMMEDIATELY — do not reload, do not signal workers.

### Phase 5 — Reload (not restart) the live service

Reload preserves in-flight workers / connections; restart kills them. If reload semantics require draining, give the drain command its own timeout and rollback path.

### Phase 6 — Post-cutover smoke

Repeat Phase 1's command verbatim. Same pilot hosts. Same tuple shape.

### Phase 7 — Pre/post diff

Byte-equal pre and post tuples → cutover succeeded; print SUCCESS + final state (md5 of artefact, size delta, key directives present).

Any mismatch → rollback hook fires automatically. Do NOT proceed further. Capture the post-rollback smoke as a third snapshot for forensic comparison.

### Phase 8 — Confirm hybrid is the active config

Re-read the active artefact and grep for the directive(s) the cutover was supposed to add. Print counts. This is a paranoia step, but it catches the case where the swap silently failed (filesystem snapshot, AppArmor profile, immutable bit, race with another operator).

---

## Auto-rollback Hook

Defined once at the top of the script:

```bash
rollback() {
    echo "[rollback] restoring active config from $BACKUP" >&2
    sudo cp -a "$BACKUP" "$ACTIVE"
    if sudo <validator>; then
        sudo <reload>
        echo "[rollback] reload after restore done" >&2
    else
        echo "[rollback] FATAL: validator failed even after restore" >&2
        exit 99
    fi
}
```

Called from Phase 4 (validator-fail), Phase 5 (reload-fail), Phase 7 (smoke-mismatch). Exit 99 is reserved for "rollback itself failed" — operators see this and intervene manually.

---

## Smoke-Test Tuple Shape

```
<response_code> <content_type> <size> <redirect_target>
```

Status-code-only smoke misses semantic regressions:

- 301 → 301 with different `Location` (host renamed, path relocated)
- 302 → 200 with empty body (route fell through)
- 200 → 200 with size changed by 90% (page rendered, content broken)

Source pattern: in a cross-stack relative-path bug, the `(status, location, body_size)` tuple detected a 301 → 500 mismatch within seconds where status-only smoke would not. The lesson generalises to every cutover where the pre/post pair must hold.

---

## Anti-Patterns to Avoid

| Anti-pattern | Why bad | Correct form |
|--------------|---------|--------------|
| Skip pre-condition check, "operators always have it set up" | Pre-condition violations will eventually happen; making them implicit means the failure mode is mysterious | Encode invariants in Phase 0; refuse to start |
| Use `restart` instead of `reload` | Kills in-flight requests; multiplies blast radius on bad config | Use `reload`; preserve workers across config-fail |
| Smoke against synthetic targets only | Real traffic includes redirect chains, cache-control, content-type quirks | Smoke against actual pilot hostnames; capture full tuple |
| Single backup, overwritten on retry | Round 2 retry destroys the Round 1 backup; no forensic trail | Each round writes its own `.PRE-CUTOVER.<TS>` snapshot |
| Hard-code pilot host list inside the cutover script | Whitelist refresh requires script edit; pattern erodes over time | Accept `--pilot-hosts <file>` flag; default to a sensible set |
| No paranoia step (Phase 8) | Silent swap failures (filesystem snapshot, AppArmor, etc.) → cutover claims SUCCESS but live config is unchanged | Re-read the active artefact post-reload and grep for added directives |

---

## Source Pattern

A multi-host pilot cutover where Round 1 hit a cross-stack relative-path bug, auto-rollback fired in under 30 seconds, the mitigation was codified, and Round 2 succeeded in ~20 seconds end-to-end with all pilot hosts pre/post identical. The 8-phase pattern is the distillation.