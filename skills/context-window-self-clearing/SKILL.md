---
name: context-window-self-clearing
description: Preserve Datarim task continuity while orchestrated Claude Code or Codex sessions compact or clear context at deterministic pressure thresholds.
model: inherit
current_aal: 1
target_aal: 3
---

# Context-Window Self-Clearing

Use this skill only for orchestrator-launched Claude Code and Codex sessions
that explicitly enable context-window automation. It is default-off.

## Contract

1. Read the active task snapshot first. Bind the active task-description path,
   last completed snapshot stage, snapshot path, and snapshot digest into a
   private transaction before sending a reset instruction.
2. Pressure has TWO arms and the stricter verdict wins.

   **Absolute arm (primary).** Below 200000 tokens of working set is `no_op`,
   200000 through 279999 is `selective_drop`, 280000 and above is `full_clear`.
   Ceilings are overridable per deployment via `DR_CTX_SOFT_TOKENS` and
   `DR_CTX_HARD_TOKENS`.

   **Percentage arm (retained).** Below 75 percent is `no_op`, 75 through 89 is
   `selective_drop`, 90 through 100 is `full_clear`. A private exact-label
   policy may select a mode only at or above its declared floor, never below 50.

   A percentage alone cannot express pressure, because it hides its
   denominator: 75 percent of a 200k window is 150k tokens, while 75 percent of
   a 1M window is 750k. Attention degrades with the LENGTH of the accumulated
   history, not with its ratio to a limit, so a larger window is headroom for
   one large read — never a licence to accumulate proportionally more. A
   threshold written only as a percentage silently changes meaning when the
   runtime's window changes, which is how a session reached 98 percent of a
   large window while every declared threshold read as satisfied.

   An orchestrator that cannot obtain a token count MUST still apply the
   percentage arm, and MUST treat the missing count as a gap to close rather
   than as evidence of low pressure.
3. Use only these fixed instructions:
   - Codex selective: `/compact`
   - Claude selective: `/compact Preserve active Datarim task pointer last completed phase current plan open verification findings and next action`
   - full clear: `/clear`
4. Claim transaction state before terminal input. A failed or crashed claim is
   ambiguous and must be reconciled; never replay it automatically.
5. After full clear, accept only a changed conversation marker bound to the
   same runtime instance, launch incarnation, and pane, revalidate the snapshot digest, then send
   `/dr-next <TASK-ID>`. After selective compaction, a matching PostCompact
   marker completes the transaction exactly once.
6. Never persist raw pane, prompt, assistant, notify, or rollout content.

## Trust boundary

An unsandboxed runtime hook and an ordinary agent tool shell run as the same OS
user. HMAC tags therefore protect private-state integrity, ordering, replay,
and pane correlation; they do not prove vendor-event origin. Automation
requires both `key_injection: true` and
`context_window.trust_same_uid_runtime: true`. Enabling both explicitly trusts
that same-UID runtime domain for the three fixed reversible actions above.

## Recovery

Use `context_window_controller.sh reconcile` to report or abort an ambiguous
transaction. Use `context_window_setup.sh doctor --recover-stale-instances`
only after the helper proves the old tmux socket/server epoch and process birth
are gone, the current epoch differs, and no nonterminal transaction references
the instance. Never delete active mappings merely to free capacity.

Continuity source of truth: `skills/dr-next-snapshot-replay/SKILL.md`.
