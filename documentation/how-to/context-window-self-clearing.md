# Enable Context-Window Self-Clearing

The `dr-orchestrate` plugin can compact or clear an orchestrated Claude Code or
Codex session before its context window is exhausted. It checkpoints the active
Datarim task pointer and last completed phase before terminal input, then uses
snapshot-first `/dr-next` replay after a full clear.

## Enable

Copy `plugins/dr-orchestrate/user-config.template.yaml` to the private
`user-config.yaml`, set mode 0600, and set both gates:

```yaml
key_injection: true
context_window:
  enabled: true
  trust_same_uid_runtime: true
  policy_label: ""
```

Both booleans are required. This opt-in trusts Claude Code or Codex and its
unsandboxed same-UID tool processes for lifecycle-marker origin. Integrity tags
prevent accidental corruption, replay, and cross-pane confusion; they are not
vendor provenance.

Optionally preflight each private overlay before starting the orchestrator:

```bash
bash plugins/dr-orchestrate/scripts/context_window_setup.sh render --runtime claude
bash plugins/dr-orchestrate/scripts/context_window_setup.sh render --runtime codex
```

Each new orchestrated tmux session registers its pane, task, process birth,
socket, and epoch automatically, then launches with the private overlay. A dead
pane is replaced under the same lifecycle lock before respawn. Replacement
reuses the pane's bounded instance slot but assigns a fresh unpredictable
incarnation, rotates its capability, and publishes an old-key claim chained to
a new-key finalization marker. Runtime hooks, pressure checkpoints, lifecycle
markers, and transactions must match that incarnation, so a delayed hook from
the prior launch fails closed. Crash recovery restores the old slot before the
finalization marker or verifies both sides of the chain before finalizing it.
Claude receives a private `--settings` overlay. Codex receives the uniquely
named `datarim-orchestrate-context` profile. Global Claude and Codex
configuration is not overwritten. In Codex, review and trust the lifecycle
hooks through `/hooks`; never use a bypass-trust flag.

## Teach an exact policy label

Set `context_window.policy_label` to a safe label and create the owner-private
policy file configured by `DR_CONTEXT_POLICY_FILE`:

```text
deep-review	selective_drop	75
handoff	full_clear	90
```

Labels are exact data-only matches. They select an enum and never become shell
or tmux input. The immutable minimum threshold is 50 percent.

## Diagnose and recover

```bash
bash plugins/dr-orchestrate/scripts/context_window_setup.sh doctor
bash plugins/dr-orchestrate/scripts/context_window_controller.sh reconcile \
  --transaction <id> --action report
```

Abort an ambiguous transaction only after reviewing its pointer evidence. For
a missed teardown after a tmux-server restart, run
`doctor --recover-stale-instances`; the helper fails closed unless a live tmux
server supplies a distinct current epoch and the stale socket, process-birth,
and nonterminal-reference checks all pass.

## Disable and roll back

Set `context_window.enabled: false`, close the orchestrated sessions, then run:

```bash
bash plugins/dr-orchestrate/scripts/context_window_setup.sh remove --runtime claude
bash plugins/dr-orchestrate/scripts/context_window_setup.sh remove --runtime codex
```

Removal refuses symlinks, hard links, foreign ownership, unsafe permissions,
or non-Datarim content. This batch does not change framework or plugin versions
and performs no release or deployment.
