# Finalize a completed task

Use `/dr-finalize TASK-ID` after implementation and verification. It runs or
reuses a current `/dr-archive`, publishes documentation through the project's
normal route, commits and pushes only task-owned files, and cleans only
ledgered work after checking merge state and clean checkouts. Record created
worktrees, branches, temporary paths, processes, and containers at creation
time using the helper. For example, after creating a worktree and branch:

```bash
python3 .datarim-runtime/dev-tools/finalize-safety.py add --ledger datarim/finalize/TASK-ID.json --kind worktree --value "$ABSOLUTE_WORKTREE_PATH"
python3 .datarim-runtime/dev-tools/finalize-safety.py add --ledger datarim/finalize/TASK-ID.json --kind branch --value "$BRANCH_NAME"
```

For temporary files, use `--kind path --value "$ABSOLUTE_PATH" --workspace
"$DATARIM_ROOT"`. The helper creates the ledger if missing and safely
deduplicates entries. Do not hand-edit it. The command reports a status
for each step and preserves anything with uncertain ownership.

To let autonomous runs reach finalization, set `autonomy.finalize: on_request`
or `always` under `autonomy:` in `datarim/config.yaml`. For `on_request`, put
`finalize_requested: true` in the task init frontmatter. Use
`python3 .datarim-runtime/dev-tools/resolve-finalize-mode.py --root .
--task-id TASK-ID` to inspect the effective mode and source. The user-global
setting lives in `$XDG_CONFIG_HOME/datarim/config.yaml` or
`~/.config/datarim/config.yaml`; project setting overrides it. `off` keeps
the autonomous route before archive.
