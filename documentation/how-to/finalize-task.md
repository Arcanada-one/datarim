# Finalize a completed task

Use `/dr-finalize TASK-ID` after implementation and verification. It runs or
reuses a current `/dr-archive`, publishes documentation through the project's
normal route, commits and pushes only task-owned files, and cleans only
ledgered work after checking merge state and clean checkouts. Record created
worktrees, branches, temporary paths, processes, and containers in
`datarim/finalize/TASK-ID.json` at creation time. The command reports a status
for each step and preserves anything with uncertain ownership.

To let autonomous runs reach finalization, set `autonomy.finalize: on_request`
or `always` under `autonomy:` in `datarim/config.yaml`. For `on_request`, put
`finalize_requested: true` in the task init frontmatter. Use
`python3 .datarim-runtime/dev-tools/resolve-finalize-mode.py --root .
--task-id TASK-ID` to inspect the effective mode and source. The user-global
setting lives in `$XDG_CONFIG_HOME/datarim/config.yaml` or
`~/.config/datarim/config.yaml`; project setting overrides it. `off` keeps
the autonomous route before archive.
