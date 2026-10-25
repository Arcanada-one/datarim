# Task finalization

`/dr-finalize` coordinates archive, documentation publication, task-owned
commits and pushes, safe return to each repository's observed default branch,
task worktree and merged-branch cleanup, task-owned temporary cleanup,
configured tracker completion, and one final report. It records each step as
`done`, `skipped: <reason>`, `failed: <reason>`, or `not measured`. The task's
ownership ledger is `datarim/finalize/{TASK-ID}.json`; an item absent from it
cannot be deleted. `dev-tools/finalize-safety.py add` creates a missing ledger,
atomically records exact task-owned resources, and deduplicates entries. The
`path`, `worktree`, and `branch` checks are read-only and additionally refuse
unmerged branches, dirty checkouts, tracked files, and unsafe paths. Each
resource-creating stage must call `add` at creation time, including interactive
runs; agents never edit the ledger JSON directly.

The supported `--kind` values are `worktree`, `branch`, `path`, `process`, and
`container`. Worktree and temporary-path values are absolute; a temporary
path also requires `--workspace` and must be inside it. A process identity is
`PID:start-tick` so a recycled PID is not enough to claim ownership. A ledger
entry only permits the later safety check; it does not itself authorize removal.

`autonomy.finalize` is `off` by default, `on_request`, or `always`. Set it in
project `datarim/config.yaml` or user-global
`$XDG_CONFIG_HOME/datarim/config.yaml` (default `~/.config/datarim/config.yaml`).
Project config wins. A task request is `finalize_requested: true` in the
init-task frontmatter. It activates `on_request`, but cannot override `off`.
`always` runs without a task request. `/dr-auto` and `/dr-orchestrate` use the
resolver after passing compliance and evolution; `/dr-doctor` and `/dr-status`
show the effective value and source. The same paths work when a shared/global
runtime is linked: project configuration remains project-specific.

Tracker integration and final-status mapping belong in
`datarim/config/tracker.json`. Without them, finalization reports
`not applied: tracker integration is not configured` and never claims a
tracker transition. A project's tracker policy and operator authority remain
in force.
