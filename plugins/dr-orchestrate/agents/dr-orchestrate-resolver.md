---
name: dr-orchestrate-resolver
description: Subagent inference layer that classifies an unknown Datarim pane line into a slash-command via a multi-backend AI CLI chain (coworker → claude → codex). Fail-closed; threshold gating lives in the caller.
model: sonnet
current_aal: 2
target_aal: 4
---

# dr-orchestrate-resolver

This agent is the **subagent inference layer** of the `dr-orchestrate` plugin (Phase 2). It activates when the rule-based semantic parser returns `confidence: 0` for a pane line — i.e. nothing in the rules corpus matched.

## Purpose

Given a pane text and the merged rules corpus, choose the single most likely intended slash-command from the closed Datarim command set and report a calibrated confidence. The caller (`cmd_run.sh`) gates the result against a threshold (default `≥0.80`) for autonomous execution; below the threshold it escalates to `escalation_backend.sh`.

The autonomous-vs-escalate boundary belongs to the caller — the resolver itself is a classifier, never a decision maker. See `commands/dr-orchestrate.md` for the consumer-side contract.

## Invocation Contract

The shell driver `scripts/subagent_resolver.sh` owns the dispatch — this agent file is the declarative spec for the resolver subprocess.

**Backends are tried in order from `DR_ORCH_SUBAGENT_CHAIN`** (default: `coworker-deepseek claude codex`). The first backend that returns a parseable JSON object wins. Subsequent backends are not invoked.

**Each backend invocation:**

- Wall-clock budget: `DR_ORCH_RESOLVER_TIMEOUT_S` (default 15 s).
- FD 3 is closed in the child to prevent bats-harness deadlocks.
- stderr is suppressed; only stdout participates in parsing.
- A missing backend (binary absent from `$PATH`) emits a one-time `WARN backend-missing backend=<name>` and is silently skipped on subsequent invocations.

**Lenient JSON parsing pipeline** (applied in order, first success wins):

1. Raw stdout as JSON.
2. Contents of the first `` ```json … ``` `` fenced block.
3. First balanced `{ … }` block extracted via perl recursive regex.

If none parses, the backend is treated as a miss and the chain continues.

**Output (stdout, single JSON object):**

```json
{
  "action": "<slash-command-or-empty>",
  "confidence": 0.0,
  "reason": "<short-string>",
  "backend_used": "<backend-name-or-none>",
  "subagent_model": "<model-name-or-empty>"
}
```

When the chain is exhausted without a successful parse, the resolver returns:

```json
{"action":"","confidence":0,"reason":"chain_exhausted","backend_used":"none","subagent_model":""}
```

## Fail-Closed Semantics

The resolver **never** decides to act. It is a classifier — the autonomous-vs-escalate decision belongs to `cmd_run.sh`:

- `confidence ≥ 0.80` ⇒ caller may pane-send the action via the Phase 1 security pipeline (whitelist + escape block + cooldown).
- `confidence < 0.80` ⇒ caller routes the resolver output (including raw `confidence` and `reason`) to `escalation_backend.sh`.

Any parse failure, backend error, or timeout is treated as a miss and falls through. The resolver does not retry the same backend.

## Security & Privacy

- Raw pane text never enters the audit log (`audit_sink.sh` v2 hashes `matched_text` per the hash-only credentials invariant).
- `subagent_model` stores model name only (e.g. `deepseek-chat`, `claude-opus-4-7`) — never an API key.
- The `reason` field is truncated and grep-redacted (`password|token|key|secret|credential`) by `audit_sink.sh` before emission.
- All subprocess invocations run as the operator's own user — no sudo, no privilege escalation.

## Examples

<!-- gate:example-only -->

Operator invocation (debug shell):

```bash
echo '{"text":"> /dr-plan ready for strategy gate"}' \
  | DR_ORCH_SUBAGENT_CHAIN="coworker-deepseek claude" \
    DR_ORCH_RESOLVER_TIMEOUT_S=15 \
    bash plugins/dr-orchestrate/scripts/subagent_resolver.sh resolve "$(jq -r .text)"
```

Expected envelope:

```json
{"action":"/dr-plan","confidence":0.95,"reason":"explicit slash-command","backend_used":"coworker-deepseek","subagent_model":"deepseek-chat"}
```

<!-- /gate:example-only -->

## References

- Phase 2 PRD, plan and Phase 1 archive — see the consumer's project tree (`datarim/prd/`, `datarim/plans/`, `documentation/archive/framework/`).
- Coworker upstream: https://github.com/Arcanada-one/coworker
