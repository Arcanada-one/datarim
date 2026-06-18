---
name: stage-snapshot-writer
description: Producer contract for per-task stage snapshots written to datarim/snapshots/{TASK-ID}.snapshot.md with overwrite semantics and an 8 KB hard cap.
current_aal: 1
target_aal: 2
---

# Stage Snapshot Writer

Every `/dr-*` command that emits a CTA block ([definition](../cta-format/SKILL.md)) writes its final operator-visible response to `datarim/snapshots/{TASK-ID}.snapshot.md` as its terminal step. The snapshot is the primary context source for `/dr-next` and `/dr-orchestrate` after `/clear` or after the terminal is closed.

## Contract

| Aspect | Value |
|--------|-------|
| Producer touchpoint | `skills/cta-format/SKILL.md` § Snapshot Emission (single producer, not N) |
| Entry point (canonical) | `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh` — invoke as `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh" <flags>`. The wrapper forces a bash interpreter; the underlying function relies on `BASH_SOURCE[0]` and dies silently under a zsh-parent shell (the default on macOS), so agents MUST call the wrapper, not the function directly. |
| Underlying function | `scripts/lib/snapshot-writer.sh::write_stage_snapshot` — requires `source` under bash; do NOT exec or invoke directly from a zsh-spawned Bash-tool call. |
| Path | `datarim/snapshots/{TASK-ID}.snapshot.md` |
| Lock | `datarim/snapshots/.lock.{TASK-ID}` (mkdir-based, reuses `acquire_plugin_lock`) |
| Lock timeout | env `DR_SNAPSHOT_LOCK_TIMEOUT` (default 60 s) |
| File size cap | 8192 bytes total (frontmatter + body); body truncated with marker on overflow |
| Truncation marker | `<!-- snapshot-truncated, full response in session jsonl -->` |
| Permissions | snapshot file `chmod 600`, lock dir `chmod 700` |
| Semantics | overwrite — a second call for the same stage replaces the file in full |
| Kill switch | `DATARIM_DISABLE_SNAPSHOT=1` → writer becomes a no-op |

## Inputs

All arguments are named (`--flag value`) and forwarded verbatim by the wrapper:

```bash
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh" \
    --root <DATARIM_ROOT> \             # absolute path to repo root
    --task <TASK-ID> \                  # ^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$
    --stage <plan|prd|do|qa|verify|auto|...> \
    --command </dr-name> \              # literal "/dr-<name>"
    --captured-by <agent|operator> \
    --recommended-next </dr-name> \     # primary CTA option, slash-prefixed
    --options-file <path> \             # newline-separated "</dr-*> | <purpose>"
    --body-file <path> \                # rendered Summary + CTA (≤ 8 KB after trim)
    [--captured-at <ISO8601 UTC>]       # default $(date -u +%FT%TZ)
```

Call the wrapper, never the bare `write_stage_snapshot` function — see § Contract
(Entry point) for why the function dies silently under a zsh-parent shell.

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
  - "/dr-do <TASK-ID> | execute the plan"
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
| 3 | lock-timeout (see `DR_SNAPSHOT_LOCK_TIMEOUT`) |

## Security controls (Appendix A cross-link)

- **T-1 path traversal:** TASK-ID validated against `^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$`; reject otherwise.
- **T-2 shell injection:** body read via `--body-file` (no shell expansion); frontmatter via quoted heredoc (Security Mandate S1).
- **T-3 concurrent writers:** mkdir lock, write-temp-rename (atomic on POSIX).
- **T-5 secret leak:** `chmod 600` on snapshot file; `.gitignore` covers `datarim/snapshots/`.
- **T-7 symlink attack:** writer unlinks pre-existing symlink at target before rename.

## Examples

```bash
# From a /dr-* command after emitting the CTA block:
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh" \
    --root "$REPO_ROOT" \
    --task "<TASK-ID>" \
    --stage plan \
    --command /dr-plan \
    --captured-by agent \
    --recommended-next /dr-do \
    --options-file /tmp/options.$$ \
    --body-file /tmp/body.$$
```

## Fail-closed contract

The snapshot is a **code-managed artefact** — overwrite semantics, the 8 KB cap,
the mkdir lock, frontmatter validation, and `chmod 600` are all enforced by the
writer. If the wrapper (or its underlying library) cannot be located or invoked,
the correct fail-closed behaviour is to **emit a single stderr warning line and
continue** (V-AC-7) — the snapshot is best-effort context for `/dr-next`, never a
blocker.

Do **NOT** hand-write `datarim/snapshots/{TASK-ID}.snapshot.md` "to the known
schema" as a substitute. A hand-authored file bypasses every guarantee above
(no atomic rename, no lock, no size cap, no permission hardening, no frontmatter
validation) and silently diverges from the contract the consumers
(`/dr-next`, `/dr-orchestrate`) rely on. Writer unreachable ⇒ warn-and-skip, not
imitate. Resolve the wrapper via `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh`
(falls back to the default symlinked runtime when `DATARIM_RUNTIME` is unset).

## Related

- `skills/cta-format/SKILL.md` § Snapshot Emission — the only producer touchpoint
- `skills/dr-next-snapshot-replay/SKILL.md` — consumer side
- `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-stage-snapshot-on-exit.sh"` — post-CTA advisory gate
- `scripts/lib/plugin-system.sh::acquire_plugin_lock` — lock primitive (reused)
- `feedback memory feedback_no_flock_on_macos` — rationale for mkdir-lock (POSIX flock is unreliable on macOS over NFS/SMB)
