---
name: stage-snapshot-writer
description: Producer contract for per-task stage snapshots — final operator-visible /dr-* response persisted to datarim/snapshots/{TASK-ID}.snapshot.md with overwrite semantics, mkdir-based atomic lock, 8 KB hard cap.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Stage Snapshot Writer

Каждая `/dr-*` команда, эмитирующая CTA-блок, как терминальный шаг пишет финальный operator-visible ответ в `datarim/snapshots/{TASK-ID}.snapshot.md`. Снапшот служит primary context-source для `/dr-continue` и `/dr-orchestrate` после `/clear` или закрытия терминала.

## Contract

| Aspect | Value |
|--------|-------|
| Producer touchpoint | `skills/cta-format.md` § Snapshot Emission (1 место, не N) |
| Implementation | `scripts/lib/snapshot-writer.sh::write_stage_snapshot` |
| Path | `datarim/snapshots/{TASK-ID}.snapshot.md` |
| Lock | `datarim/snapshots/.lock.{TASK-ID}` (mkdir-based, reuses `acquire_plugin_lock`) |
| Lock timeout | env `DR_SNAPSHOT_LOCK_TIMEOUT` (default 60 s) |
| File size cap | 8192 bytes total (frontmatter + body); body truncated with marker on overflow |
| Truncation marker | `<!-- snapshot-truncated, full ответ см. session jsonl -->` |
| Permissions | snapshot file `chmod 600`, lock dir `chmod 700` |
| Semantics | overwrite — повторный вызов той же стадии полностью замещает файл |
| Kill switch | `DATARIM_DISABLE_SNAPSHOT=1` → writer становится no-op |

## Inputs

Все аргументы — named (`--flag value`):

```
write_stage_snapshot \
    --root <DATARIM_ROOT> \             # абсолютный путь до repo root
    --task <TASK-ID> \                  # ^[A-Z][A-Z0-9-]+-[0-9]{4,5}$
    --stage <plan|prd|do|qa|verify|...> \
    --command </dr-name> \              # литерал «/dr-<name>»
    --captured-by <agent|operator> \
    --recommended-next </dr-name> \     # primary CTA option, slash-prefixed
    --options-file <path> \             # newline-separated «</dr-*> | <purpose>»
    --body-file <path> \                # rendered Summary + CTA (≤ 8 KB after trim)
    [--captured-at <ISO8601 UTC>]       # default $(date -u +%FT%TZ)
```

## Outputs

`datarim/snapshots/{TASK-ID}.snapshot.md`:

```yaml
---
task_id: <TASK-ID>
artifact: stage-snapshot
schema_version: 1
stage: plan
command: /dr-plan
captured_at: 2026-05-21T13:45:00Z
captured_by: agent
recommended_next: /dr-do
options:
  - "/dr-do <TASK-ID> | реализация плана"
  - "/dr-design <TASK-ID> | ratify writer API"
  - "/dr-status | escape hatch"
size_bytes: 6432
truncated: false
---

<rendered Summary + Gate Results + CTA-блок; ≤ 8192 bytes total file>
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | snapshot written |
| 1 | IO error / argument validation failure |
| 2 | usage error (missing flag) |
| 3 | lock-timeout (см. `DR_SNAPSHOT_LOCK_TIMEOUT`) |

## Security controls (Appendix A cross-link)

- **T-1 path traversal:** TASK-ID validated against `^[A-Z][A-Z0-9-]+-[0-9]{4,5}$`; reject otherwise.
- **T-2 shell injection:** body read via `--body-file` (no shell expansion); frontmatter via quoted heredoc (Security Mandate S1).
- **T-3 concurrent writers:** mkdir lock, write-temp-rename (atomic on POSIX).
- **T-5 secret leak:** `chmod 600` on snapshot file; `.gitignore` covers `datarim/snapshots/`.
- **T-7 symlink attack:** writer unlinks pre-existing symlink at target before rename.

## Examples

```bash
# From a /dr-* command after emitting the CTA block:
write_stage_snapshot \
    --root "$REPO_ROOT" \
    --task "<TASK-ID>" \
    --stage plan \
    --command /dr-plan \
    --captured-by agent \
    --recommended-next /dr-do \
    --options-file /tmp/options.$$ \
    --body-file /tmp/body.$$
```

## Related

- `skills/cta-format.md` § Snapshot Emission — единственная producer touchpoint
- `skills/dr-continue-snapshot-replay.md` — consumer-сторона
- `dev-tools/check-stage-snapshot-on-exit.sh` — post-CTA advisory gate
- `scripts/lib/plugin-system.sh::acquire_plugin_lock` — lock primitive (reused)
- `feedback memory feedback_no_flock_on_macos` — обоснование mkdir-lock (POSIX flock ненадёжен на macOS через NFS/SMB)
