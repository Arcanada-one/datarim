# How-to: Stage Snapshots for `/dr-next` Context Resume

**Audience:** operators returning to a Datarim task after `/clear` or a closed terminal.
**Introduced in:** v2.13.0 (TUNE-0254).

This how-to explains the per-task stage-snapshot mechanism: what gets persisted, where, how `/dr-next` and `/dr-orchestrate` consume it, and how to disable / inspect it.

## What is a snapshot?

After each `/dr-*` finishes, the agent writes its final operator-visible response (Summary + Gate Results + CTA block) to:

```
datarim/snapshots/{TASK-ID}.snapshot.md
```

Each file is small (≤ 8 KB), `chmod 600`, gitignored, and overwritten on the next stage of the same task. The frontmatter declares `stage`, `command`, `captured_at`, `recommended_next` (the primary CTA option emitted by the previous stage), and a full `options[]` list.

## How is it produced?

Every `/dr-*` command runs through `skills/cta-format.md` § Snapshot Emission as its terminal step. There is **one producer touchpoint** — adding a new `/dr-*` command automatically inherits snapshot emission without per-command patches. Producer contract: `skills/stage-snapshot-writer.md`. Implementation: `scripts/lib/snapshot-writer.sh`.

## How is it consumed?

`/dr-next {TASK-ID}` reads the snapshot **first** (Step 2.5 «Snapshot-First Read» — before task-description / init-task / activeContext). If valid, it emits a replay-prompt with the canonical template:

```
<recommended-CTA>

ищи способ исследовать все проблемы и ответить на все вопросы самостоятельно. выполняй за оператора все необходимые шаги и требования, которые можешь сделать сам. не создавай FU подзадачи, если они уровня 1, а решай их в этом же цикле до полного решения.
Find a way to investigate all problems and answer all questions yourself. Perform on behalf of the operator every step and requirement you can do yourself. Do not spawn FU sub-tasks for Level-1 work — resolve them in the same cycle to completion.

done before:
<snapshot body>
```

`/dr-orchestrate` does the same in its resume-from-queue path before invoking `subagent_resolver.sh`, passing `recommended_next` as a `--hint`.

Consumer contract (including the natural-language CTA-selection heuristic with three worked examples): `skills/dr-next-snapshot-replay.md`.

## Fallback when no snapshot exists

If the snapshot file is missing or its frontmatter fails validation (`dev-tools/check-stage-snapshot-on-exit.sh --validate-frontmatter --task <ID>` exit ≠ 0), the consumer **silently** falls through to the legacy Read pipeline — no warning lines, no behaviour change for first-time `/dr-next` invocations.

## Concurrency & locks

Snapshot writes use a mkdir-based atomic lock (`datarim/snapshots/.lock.{TASK-ID}`) — macOS-portable, no `flock` dependency. Default lock timeout 60 s; override via `DR_SNAPSHOT_LOCK_TIMEOUT=N`. Two parallel writers compete cleanly: one writes, the other waits or exits 3 on timeout. Body is never interleaved.

## Cleanup at archive

`/dr-archive` Step 0.95 moves the final snapshot out of the workspace:

```
datarim/snapshots/{TASK-ID}.snapshot.md
    →  documentation/archive/<subdir>/snapshots/{TASK-ID}-final-stage.md
```

Subdir resolves via the existing `prefix_to_area()` helper (Task Prefix Registry walk-up). Move-not-delete — the final snapshot is a compact task card useful for `grep`-search across the archive.

## Redaction guidance

Snapshot bodies inherit any content the agent emitted to the operator. If a `/dr-*` response would print a secret (API key, password, token), the same secret will land in the snapshot until the agent itself redacts it. Two operator-side mitigations:

- `datarim/snapshots/` is gitignored — secrets never reach git history through this path.
- File permissions are `chmod 600` — readable only by the running user.

For audited-redaction guarantees, set `DATARIM_DISABLE_SNAPSHOT=1` before invoking the sensitive `/dr-*` stage. The writer becomes a no-op.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `/dr-next` keeps reading task-description instead of snapshot | snapshot missing or malformed | `dev-tools/check-stage-snapshot-on-exit.sh --task <ID>` — exit 1 = missing, exit 2 = malformed |
| `/dr-*` returns exit 3 from writer | lock contention | another agent holds the lock; wait or increase `DR_SNAPSHOT_LOCK_TIMEOUT` |
| Body shows `<!-- snapshot-truncated, ...` | response > 8 KB cap | truncated by design; full body remains in session jsonl |
| File survives `/dr-archive` in `datarim/snapshots/` | move step skipped or failed | check `documentation/archive/<subdir>/snapshots/` — file may already be there; otherwise re-run `/dr-archive` |

## Reference

- `skills/stage-snapshot-writer.md` — producer contract
- `skills/dr-next-snapshot-replay.md` — consumer contract
- `skills/cta-format.md` § Snapshot Emission — invocation pattern
- `scripts/lib/snapshot-writer.sh` — implementation
- `dev-tools/check-stage-snapshot-on-exit.sh` — validator
- `commands/dr-next.md` § Step 2.5 — consumer touchpoint
- `plugins/dr-orchestrate/commands/dr-orchestrate.md` § Snapshot-First Resume — orchestrator touchpoint
- `commands/dr-archive.md` § Step 0.95 — cleanup-on-archive
