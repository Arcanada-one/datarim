---
id: dr-orchestrate
title: /dr-orchestrate — Self-Driving Datarim Pipeline (Phase 2)
description: "Tmux-based pipeline runner. Phase 2 adds multi-backend subagent inference for unknown prompts (autonomy L1→L2). Command and autonomy policy are core; the tmux/bot transport runner is an opt-in plugin."
usage: |
  dr-orchestrate run
  dr-orchestrate run --dry-run
  dr-orchestrate run --unknown-prompt [text]
options:
  --dry-run: "Log decisions without executing"
  --interval: "Poll cycle interval in seconds (default: 5)"
  --unknown-prompt: "Resolve a parser-miss prompt via the subagent inference chain"
autonomy: L2
phase: 2
---

# /dr-orchestrate

Phase 2 — Subagent Inference Layer (v2.4.0).

## Cycle

1. `tmux capture-pane -p -t <pane>` — captures the current pane buffer.
2. **Snapshot-First Resume.** If the buffer or job-queue identifies an active TASK-ID and `datarim/snapshots/{TASK-ID}.snapshot.md` is valid (`dev-tools/check-stage-snapshot-on-exit.sh --validate-frontmatter --task <ID>` returns exit 0), read the snapshot before invoking `semantic_parser.sh` and pass `recommended_next` to `subagent_resolver.sh` as `--hint <command>`. The snapshot read happens before resolver dispatch, so the resolver can still return a different command — the snapshot is a hint, not a constraint. If the snapshot is absent or malformed, skip this step without warning (V-AC-7 — the seventh verification acceptance criterion) and continue with prior behaviour. Consumer-side contract: `skills/dr-next-snapshot-replay/SKILL.md`.
3. `semantic_parser.sh parse` — rule-based pass returns `{command, confidence, source}`.
4. **Hit (confidence > 0)** — Phase 1 path: log `make_event` v1, JSONL append.
5. **Miss (confidence == 0)** — Phase 2 path:
   - `subagent_resolver.sh resolve` — multi-backend chain (coworker → claude → codex), 15s per backend, lenient JSON parse, FD-3 close.
   - Confidence threshold gate (default `0.80`):
     - Pass → when resolver JSON includes `action_kind`, call
       `plugins/dr-orchestrate/scripts/action_gate.sh` before autonomous execution. Space-policy
       `auto` proceeds; `operator` or invalid policy routes to escalation.
       Then audit `outcome: resolved` (schema v2); decision-cooldown 60s
       enforces a single autonomous decision per pane per minute.
     - Fail / chain_exhausted → `escalation_backend.sh emit` (mock JSONL by default; the `dev-bot` backend remains a stub until a real consumer service exists) + audit `outcome: escalated`.
6. Every `tmux send-keys` still passes through the security floor: whitelist → escape-block → micro-cooldown (500 ms) + decision-cooldown (60 s) → fail-closed.

## Configuration (user-config.yaml)

```yaml
subagent:
  fallback_chain: ["coworker-deepseek", "claude", "codex"]
  timeout_s: 15
  confidence_threshold: 0.80
escalation:
  backend: "mock"
  mock_log: ~/.local/share/dr-orchestrate/escalation.jsonl
```

## Audit (schema v2)

- `make_event_v2` — adds fields `schema_version: 2`, `confidence`, `subagent_model`, `backend_used`, `escalation_backend`, `stage` (parse / resolve / escalate), `outcome` (matched / resolved / escalated / blocked_decision_cooldown), `reason` (grep-redacted).
- Phase 1 v1 events are preserved for the rule-hit path — backwards compatibility.
- `matched_text_hash` (sha256) — V-AC-12 (the twelfth verification acceptance criterion — pane-text never logged in raw form) invariant preserved; raw pane text never reaches the log.

## Security Floor (Phase 2 extensions)

- `flock -n` wrapper around cooldown read-write on Linux hosts (V-AC-21 — twenty-first verification acceptance criterion — race-safe cooldown).
- macOS fallback: one-time WARN, non-atomic semantics (Phase 1 behaviour).
- Decision-cooldown (60 s) — separate gate for autonomous decisions through the resolver path.
- Reason-redaction: `password=`, `token=`, `secret=`, `credential=`, `api_key=` elided to `<REDACTED>` before write.

<!-- gate:example-only -->

## CLI examples

```bash
# default Phase 2 cycle: parse → (rule-hit | resolver → autonomous-or-escalate)
dr-orchestrate run --pane "%5"

# dry-run отображает baseline без mutation
dr-orchestrate run --dry-run

# manual resolver invocation with inline text
dr-orchestrate run --unknown-prompt "operator paste: > /dr-prd strategy gate"
```

Inspect audit:

```bash
tail -1 ~/.local/share/datarim-orchestrate/audit-$(date -u +%Y-%m-%d).jsonl | jq .
```

<!-- /gate:example-only -->

## Architecture boundary

- **Core (no plugin needed):** this command file, `dev-tools/resolve-space-autonomy.sh`, `dev-tools/lib/space-autonomy.sh`, `dev-tools/fb-policy-loader.sh`, `dev-tools/rules/fb-rules.yaml` (autonomy floor + policy map). The autonomy floor and policy map resolve without enabling the plugin.
- **Plugin (opt-in — `dr-plugin enable <path>/plugins/dr-orchestrate`):** tmux runner, subagent inference chain, bot/HTTP transport, Redis pub/sub, HMAC audit, fleet scripts, content-consilium fan-out. Enable the plugin to use `/dr-orchestrate run`.
- Resolver agent: `agents/dr-orchestrate-resolver.md` — plugin-backed; non-functional without the `dr-orchestrate` plugin's `subagent_resolver.sh`. See plugin README for setup.
- Plugin README: `plugins/dr-orchestrate/README.md`
- Provenance: `docs/evolution-log.md`
