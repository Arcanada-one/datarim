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
2. Treat pressure below 75 percent as `no_op`, 75 through 89 as
   `selective_drop`, and 90 through 100 as `full_clear`. A private exact-label
   policy may select a mode only at or above its declared floor, never below 50.
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
