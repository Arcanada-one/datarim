# CLI Conflict Resolver — Prompt Template

A prompt template for running **Claude CLI as an embedded conflict-resolver** in shell scripts, cron jobs, and CI/CD pipelines.

## Origin

Pattern derived from a multi-host git-pull resolver script. Smoke-tested: 3/3 successful pulls, correct exit code, reliable decision logic.

## Invocation Pattern

```bash
# nosec-extract
CLAUDE_BIN=/home/dev/.local/bin/claude
CLAUDE_TIMEOUT=300
CLAUDE_MODEL=sonnet  # or opus for complex conflicts

result="$(timeout "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" \
    --print \
    --permission-mode bypassPermissions \
    --model "$CLAUDE_MODEL" \
    "$prompt" 2>&1)"

last_line="$(echo "$result" | tail -n 1 | tr -d '[:space:]')"
case "$last_line" in
    RESOLVED) echo "✅ resolved";;
    FAILED:*) echo "❌ Claude refused: ${last_line#FAILED:}";;
    *)        echo "⚠️ unexpected output, treat as failure";;
esac
```

## Prompt Template (parameterize per task)

```text
You are resolving a {CONFLICT_TYPE} in: {TARGET}
Working directory is already {TARGET}.

Conflict items:
{CONFLICT_LIST}

Procedure:
1. cd "{TARGET}" (if applicable)
2. For each conflict item:
   a. Read it.
   b. Resolve by choosing the most reasonable merge:
      {DECISION_RULES}
   c. {CLEANUP_STEP — for example, remove conflict markers}.
3. After ALL items resolved: {COMMIT_OR_FINALIZE_STEP}
4. Print exactly "RESOLVED" on the very last line if {SUCCESS_CRITERIA}.
5. If any conflict is too complex (semantic conflict, ambiguous business logic),
   leave items as-is and print exactly "FAILED: <one-line reason>" on the last line.

Hard constraints:
- {LIST_OF_FORBIDDEN_ACTIONS — never push, never install, never build, never touch anything outside scope}
- Time budget: {TIMEOUT}s.
```

## Concrete Example (git merge conflict resolver)

```text
You are resolving a git merge conflict in repo: $repo_dir
Working directory is already $repo_dir.

Conflict files (each contains <<<<<<< / ======= / >>>>>>> markers):
$conflict_files

Procedure:
1. cd "$repo_dir"
2. For each conflict file:
   a. Read it.
   b. Resolve by choosing the most reasonable merge:
      - Prefer additive merges (keep both sides if non-overlapping).
      - For lock files (Cargo.lock, package-lock.json, pnpm-lock.yaml, yarn.lock, uv.lock):
        prefer the incoming side (origin/main / "theirs" / HEAD-after-merge).
      - Prefer the version with newer fix references (commit IDs, dates, "fix:" prefixes).
      - Prefer the version that compiles / parses (valid JSON, valid YAML, valid syntax).
   c. Remove all conflict markers (<<<<<<<, =======, >>>>>>>).
3. After ALL files resolved: run `git add -A && git commit --no-edit`.
4. Print exactly "RESOLVED" on the very last line if commit succeeded.
5. If any conflict is too complex (semantic conflict, ambiguous business logic),
   leave files as-is and print exactly "FAILED: <one-line reason>" on the last line.

Hard constraints:
- Do NOT push.
- Do NOT touch files outside the conflict set.
- Do NOT install dependencies, run builds, or run tests.
- Do NOT modify .git/ contents directly.
- Time budget: 300s.
```

## Other Use-Cases (parameterize template)

| Use-case | CONFLICT_TYPE | TARGET | DECISION_RULES |
|---|---|---|---|
| **JSON/YAML config drift** | configuration-drift | config file path | Schema-compatible merge; prefer values that pass validation |
| **TF/Terraform state conflict** | terraform-state-merge | state file | Lock-acquire first, prefer remote state for shared resources |
| **Database migration conflict** | migration-order-conflict | migrations/ dir | Renumber to preserve dependency order, never delete applied migrations |
| **Translation file merge** | i18n-merge | locales/*.json | Keep new keys from both, conflict on same key → prefer reviewed translation |
| **Lock file merge** | lockfile-merge | package-lock.json etc. | Always prefer regenerated from current package.json (`npm i --package-lock-only`) |

## Hard Constraints — Non-Negotiable

These rules are **mandatory** in any CLI-agent-in-shell pattern (protection against runaway agents):

1. **No external state changes outside scope** — no `git push`, `npm publish`, `cargo publish`, `aws s3 cp`, or `curl POST` to production endpoints without explicit approval.
<!-- gate:example-only -->
2. **No package installs** — `npm install`, `pip install`, and `cargo add` can pull in vulnerabilities.
<!-- /gate:example-only -->
3. **No builds/tests** — too slow for cron, they can leave artifacts behind, and they can fail and block the decision.
4. **Time budget** — `timeout NNs` is mandatory. CLI Claude may think for minutes; cron must stay predictable.
5. **Machine-readable verdict** — the last line of output is exactly `RESOLVED` or `FAILED: <reason>`. No variations. The script parses `tail -n 1`.
6. **Idempotent on re-run** — if the agent has already resolved the conflict, a repeat run must detect that (e.g. `git status --porcelain` empty) and exit quickly.

## Failure Handling Pattern

```bash
# nosec-extract
if [[ "$last_line" == "RESOLVED" ]]; then
    log "✅ Claude resolved"
elif [[ "$last_line" == FAILED:* ]]; then
    log "❌ Claude refused: ${last_line#FAILED:}"
    opsbot_alert "warning" "Claude conflict resolver refused: $reason"
    # Leave the state as-is — the user resolves it manually
elif [[ -z "$last_line" ]]; then
    log "⚠️ Claude empty output — likely timeout or crash"
    opsbot_alert "warning" "CLI Claude empty output in $context"
else
    log "⚠️ Claude unexpected output: $last_line"
    # Treat unexpected output as failure, for safety
fi
```

## When NOT to Use This Pattern

- **Production deploy decisions** — too high-stakes for an autonomous agent; requires a human approval gate.
- **Security incidents** — conflicts in auth/secrets/ACL must escalate to a human, not be auto-resolved.
- **Cross-team merges** — where the conflict affects different stakeholders and the agent does not know their preferences.
- **Schema migrations with data-loss risk** — DROP COLUMN, DELETE rows, etc.

## Related Skills

- `skills/file-sync-config/SKILL.md` — full file-sync setup (where this pattern was first applied)
- `skills/security/SKILL.md` — why `bypassPermissions` mode needs hard constraints
- `skills/devops/SKILL.md` — cron-driven self-healing infrastructure
