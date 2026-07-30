# How to surface cross-KB evolution

Datarim self-evolution runs **per knowledge base**. Every managed KB (the framework's own KB
plus every project/space KB) keeps its own `datarim/history/evolution-log.md`. When a task in a
non-framework KB evolves the shared `~/.claude` runtime, the log entry lands in *that* KB's log —
so an operator who only watches the framework KB never sees it. Project-local `feedback-memory`
lessons decay locally and never surface as framework evolution at all.

`dev-tools/cross-kb-evolution-digest.sh` closes that gap. It reads the per-KB evolution-log
across an operator-configured set of KB roots and prints **one** digest with two buckets:

- **Framework evolution** — rows whose Target is a shared-runtime surface
  (`skills/`/`agents/`/`commands/`/`templates/` or `CLAUDE.md`, with or without a `~/.claude/`
  prefix). These already changed the shared runtime, elsewhere, silently.
- **Promotion candidates** — project-local lessons (`feedback-memory` category or a `memory/`
  Target) that may warrant promotion to framework evolution.

It is strictly **read-only** over every KB and never mutates or auto-applies anything.

## Configure the managed KB roots

List one workspace root (the parent of a `datarim/` directory) per line:

```
# ~/.claude/local/config/managed-kbs.conf
/path/to/framework-kb
/path/to/space-a
/path/to/space-b
```

Blank lines and `#` comments are ignored. The file is **read line-by-line, never sourced**.
Override the default path with the `CROSS_KB_EVOLUTION_CONF` environment variable, or pass roots
directly on the command line.

Seed this list from whatever authoritative registry your ecosystem already maintains (e.g. a
spaces registry). A KB absent from the list is invisible to the digest — the same failure mode
the tool exists to fix — so keep the list complete, or use `--discover` (below).

## Run it

```bash
# explicit roots
dev-tools/cross-kb-evolution-digest.sh --kb ~/framework-kb --kb ~/spaces/aether

# from a config file
dev-tools/cross-kb-evolution-digest.sh --config ~/.claude/local/config/managed-kbs.conf

# auto-discover every KB under a parent directory
dev-tools/cross-kb-evolution-digest.sh --discover ~/spaces

# only recent evolution, as JSON, written to a file
dev-tools/cross-kb-evolution-digest.sh --config managed-kbs.conf --since 2026-06-01 --json --out digest.json
```

| Flag | Effect |
|------|--------|
| `--kb <root>` | Add one KB root (repeatable). |
| `--config <file>` | Read roots from a file (missing/unreadable file → exit 2). |
| `--discover <dir>` | Glob KB roots by locating `*/datarim/history/evolution-log.md` under `<dir>`. |
| `--since <YYYY-MM-DD>` | Keep only rows on/after this date. |
| `--sync-stale <S>` | Flag a log `SYNC-STALE` when its mtime age ≥ `S` seconds. |
| `--now <EPOCH>` | Freshness-comparison test hook (default: current time). |
| `--json` | Emit machine-readable JSON (rows + per-KB status array). |
| `--out <file>` | Write atomically to a file instead of stdout (refuses a symlink target). |

## Read the per-KB status

Every configured KB always appears in a `## Per-KB status` block — nothing is silently absent.

| Status | Meaning |
|--------|---------|
| `OK (n row(s)…)` | Parsed; `n` framework/promotion rows surfaced. |
| `MISSING-ROOT` | The configured root does not exist (typo or unsynced). |
| `NO-LOG` | Root exists but has no `datarim/history/evolution-log.md`. |
| `EMPTY` | Log parsed fine but had no framework-relevant rows (in the window). |
| `PARSE-ERR` | Log had pipe-lines but no valid date-rows — a corrupt table. |
| `SYNC-STALE` | Log mtime age ≥ `--sync-stale` — possibly not synced; do not read as "no evolution". |

`MISSING-ROOT`, `NO-LOG`, `EMPTY`, and `SYNC-STALE` are distinct states on purpose: a typo'd or
unsynced root must never be mistaken for "that KB had no evolution".

## Exit codes

- `0` — aggregation completed (including all-degraded inputs — a digest never fails on bad data).
- `2` — usage error (unknown flag, malformed `--since`, missing/unreadable `--config`).
- `3` — `--out` write failure (refused symlink, missing parent dir, or I/O error).

## Safety notes

Evolution-log rows may be synced from other machines and are treated as untrusted: every cell is
inert data (never evaluated or sourced), and the Target column is classified by string prefix
**only** — it is never opened as a path, so a traversal-shaped or absolute Target is just a
string. JSON output is fully escaped. The tool writes nowhere except an explicit `--out` target.
