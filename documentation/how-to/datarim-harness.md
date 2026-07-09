# How-to — Datarim stage-probe harness

Empirical test harness verifying four axes per `/dr-*` invocation:

- **A** — Stage Header surfaces (body starts with `**{TASK-ID} · {title}**`).
- **B** — Snapshot writer health (snapshot file written + sha recorded).
- **C** — Coworker context completeness (mandate keywords in profile response).
- **D** — Cleanup invariant (`/dr-archive` removes harness directory).

## When to use

Enable when validating a new convention rolled across multiple `/dr-*` commands, or when investigating «is the convention actually surfacing in agent responses?». The harness piggy-backs on the existing snapshot-emission step, so no command-by-command instrumentation is required.

## Lifecycle

```text
                       ┌── /dr-do step 1
                       │   ▾
                       │   datarim-stage-probe-init.sh <TASK-ID>
                       │   ▾
                       │   /tmp/datarim-test-<TASK-ID>/{payload.txt, journal.md}
                       ▾
/dr-init               every subsequent /dr-*       /dr-archive
                       writes snapshot ──auto──►    cleanup
                       appends journal line         removes dir
                       (header / cta-footer
                        / snapshot sha)
```

## Enabling the harness

```text
dev-tools/datarim-stage-probe-init.sh <TASK-ID>
# ok: harness ready at /tmp/datarim-test-<TASK-ID>
```

Mode `0700`. Idempotent — re-running on an existing directory leaves it intact and appends a fresh `init · …` line.

## Journal contract

The snapshot writer (`scripts/lib/snapshot-writer.sh::write_stage_snapshot`) auto-detects the harness directory after each successful snapshot write. When the directory exists, it appends one line per call:

```
<stage> · <ISO-ts> · header-present:<y|n> · snapshot-written:y · cta-footer:<y|n> · snapshot-sha:<12-hex>
```

Detection is best-effort and operates on the body file passed to the writer:

- `header-present:y` iff first line matches `^\*\*{TASK-ID} · `.
- `cta-footer:y` iff body contains `Следующий шаг — {TASK-ID}` OR a `/dr-*` primary line referencing the TASK-ID.
- `snapshot-sha` is the first 12 hex chars of `sha256(snapshot file)`.

Fail-soft: a journal-write failure never aborts the snapshot itself (V-AC-7 contract).

## Coworker echo probe

To verify that the lightweight `coworker ask --profile doc-read` path still
surfaces Datarim conventions from the task-description context:

```text
dev-tools/datarim-stage-probe-coworker-echo.sh <TASK-ID>
# ok: keywords=4 (response saved to /tmp/datarim-test-<TASK-ID>/coworker-echo.txt)
```

The probe sends a fixed question (`List 3 Datarim conventions you must follow
when editing this file.`) with the task-description as `--paths`, captures the
response, and counts how many mandate keywords appear (Stage Header,
append-log, expectations, snapshot, frontmatter, mandate, Supreme Directive,
Diátaxis, wish_id, history-agnostic).

**Refusal on sensitive markers** — if the task-description contains tokens like `password`, `api_key`, `/etc/shadow`, `vault token`, `client_secret`, or `private_key`, the probe records `skipped:sensitive-markers` in the journal and exits 0 without invoking coworker.

## Cleanup

```text
dev-tools/datarim-stage-probe-cleanup.sh <TASK-ID>
# ok: removed /tmp/datarim-test-<TASK-ID>
```

Idempotent (exit 0 if directory never existed). Symlink-safe (exit 1 + leave symlink intact).

Typically invoked from `/dr-archive` so the harness self-cleans on task closure.

## Inspecting results

```bash
cat /tmp/datarim-test-<TASK-ID>/journal.md
```

Sample expected output (full lifecycle):

```
init · 2026-05-22T22:05:00Z · TASK-ID=TEST-9999
plan · 2026-05-22T22:10:15Z · header-present:y · snapshot-written:y · cta-footer:y · snapshot-sha:a1b2c3d4e5f6
do · 2026-05-22T22:45:30Z · header-present:y · snapshot-written:y · cta-footer:y · snapshot-sha:b7c8d9e0f1a2
qa · 2026-05-22T23:30:00Z · header-present:y · snapshot-written:y · cta-footer:y · snapshot-sha:d9e0f1a2b3c4
coworker · 2026-05-22T22:55:00Z · keywords-found:4
archive · 2026-05-22T23:45:00Z · header-present:y · snapshot-written:y · cta-footer:y · snapshot-sha:e5f6a7b8c9d0
```

A line with `header-present:n` indicates the agent missed the Stage Header convention on that stage — fail-fast signal that the `coworker-context.md` reference / Stage-Header bullet has not yet propagated.

## Disabling without uninstall

```bash
export DATARIM_DISABLE_SNAPSHOT=1
```

Suppresses both snapshot emission and the journal hook. The harness directory remains untouched; the writer simply returns 0 without writing anything.

## Forensic mode

If you want the harness directory preserved across the archive boundary (e.g. for postmortem), simply do not invoke `datarim-stage-probe-cleanup.sh`. The directory ages out of `/tmp` per the host's tmpfile policy (typically 7-30 days).

## Related

- `skills/cta-format/SKILL.md § Snapshot Emission` — canonical writer recipe and journal-hook documentation.
- `skills/coworker-context/SKILL.md` — what coworker MUST know when generating Datarim artifacts (the V-AC-5 / V-AC-12 acceptance reference).
- `dev-tools/check-stage-snapshot-on-exit.sh` — snapshot frontmatter validator (separate from harness).
