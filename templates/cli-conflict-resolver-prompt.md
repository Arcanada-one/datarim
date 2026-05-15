# CLI Conflict Resolver — Prompt Template

Шаблон промпта для запуска **Claude CLI как embedded conflict-resolver** в shell-скриптах, cron-задачах, CI/CD pipelines.

## Origin

Pattern derived from a multi-host git-pull resolver script. Smoke-tested: 3/3 successful pulls, correct exit code, reliable decision logic.

## Invocation Pattern

```bash
# nosec-extract
CLAUDE_BIN=/home/dev/.local/bin/claude
CLAUDE_TIMEOUT=300
CLAUDE_MODEL=sonnet  # или opus для сложных конфликтов

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

## Promp Template (parameterize по задаче)

```text
You are resolving a {CONFLICT_TYPE} in: {TARGET}
Working directory is already {TARGET}.

Conflict items:
{CONFLICT_LIST}

Procedure:
1. cd "{TARGET}" (если применимо)
2. For each conflict item:
   a. Read it.
   b. Resolve by choosing the most reasonable merge:
      {DECISION_RULES}
   c. {CLEANUP_STEP — например, remove conflict markers}.
3. After ALL items resolved: {COMMIT_OR_FINALIZE_STEP}
4. Print exactly "RESOLVED" on the very last line if {SUCCESS_CRITERIA}.
5. If any conflict is too complex (semantic conflict, ambiguous business logic),
   leave items as-is and print exactly "FAILED: <one-line reason>" on the last line.

Hard constraints:
- {LIST_OF_FORBIDDEN_ACTIONS — никогда не push, не install, не build, не trogать вне scope}
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

Эти правила **обязательны** в любом CLI-агент-в-shell pattern (защита от runaway agents):

1. **No external state changes outside scope** — никаких `git push`, `npm publish`, `cargo publish`, `aws s3 cp`, `curl POST` к production endpoints без explicit approval.
<!-- gate:example-only -->
2. **No package installs** — `npm install`, `pip install`, `cargo add` могут потащить уязвимости.
<!-- /gate:example-only -->
3. **No builds/tests** — слишком долго для cron, могут оставить артефакты, могут упасть и заблокировать решение.
4. **Time budget** — `timeout NNs` обязателен. CLI Claude может задуматься на минуты, cron должен быть предсказуем.
5. **Machine-readable verdict** — последняя строка output ровно `RESOLVED` или `FAILED: <reason>`. Без variations. Скрипт парсит `tail -n 1`.
6. **Idempotent on re-run** — если агент уже резолвил, повторный запуск должен detect (e.g. `git status --porcelain` empty) и быстро выйти.

## Failure Handling Pattern

```bash
# nosec-extract
if [[ "$last_line" == "RESOLVED" ]]; then
    log "✅ Claude resolved"
elif [[ "$last_line" == FAILED:* ]]; then
    log "❌ Claude refused: ${last_line#FAILED:}"
    opsbot_alert "warning" "Claude conflict resolver refused: $reason"
    # Оставить state как есть — пользователь резолвит вручную
elif [[ -z "$last_line" ]]; then
    log "⚠️ Claude empty output — likely timeout or crash"
    opsbot_alert "warning" "CLI Claude empty output in $context"
else
    log "⚠️ Claude unexpected output: $last_line"
    # Treat unexpected как failure для safety
fi
```

## When NOT to Use This Pattern

- **Production deploy decisions** — слишком high-stakes для автономного агента, требует human approval gate.
- **Security incidents** — конфликты в auth/secrets/ACL должны эскалировать к человеку, не auto-resolve.
- **Cross-team merges** — где конфликт касается разных стейкхолдеров, агент не знает их предпочтений.
- **Schema migrations с data loss риском** — DROP COLUMN, DELETE rows etc.

## Related Skills

- `skills/file-sync-config.md` — full file-sync setup (где этот pattern впервые применён)
- `skills/security.md` — почему `bypassPermissions` mode нужен hard constraints
- `skills/devops.md` — cron-driven self-healing infrastructure
