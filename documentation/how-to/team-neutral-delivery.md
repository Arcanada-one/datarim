# Team-neutral delivery and closure

Use this mode when Datarim runs in a repository shared with teammates who do not use it. The installer leaves the project's root instructions untouched. Datarim commands remain explicit entry points; the nested `datarim/AGENTS.md` applies only to Datarim work.

## Install

Answer the installer's normal Jev, client, and permission questions, then include `--team-neutral` with the returned answers token:

```sh
./install.sh --project /path/to/project --team-neutral --init <answered-flags>
```

The option is remembered on update. It exposes only `datarim/AGENTS.md`, `datarim/config.yaml`, and `datarim/local/` to Git. Review and commit those project-owned files if teammates should receive them. Task files, QA working data, credentials, runtime files, and native command adapters stay excluded. Existing root `AGENTS.md`, README, and `.gitignore` are not edited.

## Publish reports

Set a project-relative directory template in `datarim/config.yaml`:

```yaml
delivery:
  reports: reports/datarim/{task_id}
```

The only placeholder is `{task_id}`. Absolute paths, parent traversal, symlinked destinations, and paths inside private `datarim/` are refused. `/dr-qa` and `/dr-compliance` retain working reports under `datarim/`, publish a byte-identical copy at the configured path, and check that copy. Review and commit the shared report according to the project's own document rules. Without this key, the existing private-report behavior remains and the stage reports an advisory about teammate visibility.

## Close against project rules

`/dr-qa` checks both the reported failure and an ordinary successful path for a claimed fix. `/dr-compliance` checks project validators for changed instructions and sweeps active docs, review-bot learnings, agent memory, and templates when a convention changes. `/dr-archive` records every applicable project-declared post-merge or closure obligation as `done`, `not_done`, or `not_measured`. Missing evidence never becomes `done`. A fresh-context closure audit may re-check the draft archive before completion; its absence is recorded as `not_measured`.
