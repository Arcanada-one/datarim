# dr-fleet-evolution

Bash-native skill-evolution loop for the Datarim fleet model (§5.5 of the
orchestration-v2 concept). It improves the hand-authored fleet starter skills
(`skills/fleet/l1-basic` … `l5-autonomous`) from real execution signals, without
any Python/ML dependency — generation and scoring are delegated to `coworker`
(DeepSeek), and every quality check is a fail-closed Bash gate.

## Pipeline

```
collect signals  ->  generate variants  ->  constraint gates  ->  select best  ->  open PR
 (source adapters)   (coworker write)       (fail-closed)         (judged score)   (never auto-merge)
```

1. **Collect** — each registered source-adapter emits a uniform JSONL eval
   dataset; the loop merges them (dedup by `task_input`+`source`). Below the
   `--threshold` the loop skips (not an error).
2. **Generate** — `coworker write` produces `--candidates` variants of the
   skill. Bulk content (skill body, eval dataset) is passed via `--context`
   files only — never inline (Security S1).
3. **Gate** — every candidate must pass all gates in `gates/` (English-only,
   size-budget, surface bats, no-secrets). Fail-closed: one failure drops the
   candidate.
4. **Select** — among gate-passing candidates, `coworker ask` judges a
   success-rate; the highest wins (ties → smaller size).
5. **PR** — the winner is committed to a `feat/tune-0380-evolve-<level>` branch
   and pushed for human review. The loop **never** merges.

## Components

| Path | Role |
|------|------|
| `adapters/source-adapter-contract.md` | The JSONL record contract |
| `adapters/archive-adapter.sh` | Signals from task archives |
| `adapters/dr-dream-adapter.sh` | Gap signals from `/dr-dream` reflections |
| `adapters/source-adapters.conf` | Registered sources (extension-point) |
| `gates/gate-english.sh` | English-only shipped-surface gate |
| `gates/gate-size-budget.sh` | Per-candidate token-budget gate |
| `gates/gate-bats.sh` | Fleet surface-guard suite must stay green |
| `gates/gate-no-secrets.sh` | Reject secret-like content |
| `gates/run-all-gates.sh` | Fail-closed gate orchestrator |
| `lib/jsonl.sh` | JSONL emit / validate / merge helpers (jq) |
| `dev-tools/check-coworker-file-flags.sh` | Security S1 static check |
| `evolution-loop.sh` | The loop entry point |

## Usage

```bash
plugins/dr-fleet-evolution/evolution-loop.sh \
    --skill skills/fleet/l1-basic \
    --candidates 3 --threshold 5 --dry-run
```

`--dry-run` applies the winning candidate to the working tree and prints the
diff without creating or pushing a branch.

## Extending the signal sources

Add one line to `adapters/source-adapters.conf`:

```
<adapter-script>|<source-path>|<label>
```

The deferred **audit-log** source (Redis Stream traces) lands here once its
redaction layer is built — a tracked follow-up, blocked on the Phase-3 event bus
reaching `main`.

## Tests

```bash
bats tests/test-fleet-evolution-*.bats
```

External-service tests are env-gated: they `skip` (never fail) when `jq`, `bats`,
or `coworker` are unavailable.
