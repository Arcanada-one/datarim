# Initialize Datarim in a project

Datarim is installed explicitly inside a consumer project. It does not install
global rules, commands, hooks, or executables. The framework source checkout is
not a task workspace. Python 3.10 or newer is required.

1. Obtain a reviewed Datarim checkout and record its commit. Set
   `DATARIM_SOURCE` to its absolute path and `DATARIM_PROJECT` to the existing
   consumer project's absolute path. Do not point either variable at your home.
2. Combine existing project instructions into a regular `AGENTS.md`. Resolve
   conflicts before removing `CLAUDE.md`, `CLAUDE.local.md` and other instruction
   adapters. Preserve client authentication and non-instruction settings.
3. Preview and initialize:

```bash
python3 "$DATARIM_SOURCE/scripts/project_install.py" --project "$DATARIM_PROJECT" --init --dry-run
python3 "$DATARIM_SOURCE/scripts/project_install.py" --project "$DATARIM_PROJECT" --init
cd "$DATARIM_PROJECT"
source .datarim-runtime/activate.sh
jev doctor
```

The installer adds a managed Datarim section to `AGENTS.md`, creates local command
discovery files, copies a runtime into `.datarim-runtime/`, and initializes missing
`datarim/tasks.md` and `datarim/backlog.md`. Existing task files are preserved.
No Jev key is needed for plain Datarim. Start your installed agent normally, then
use the Datarim initialization command to describe the first task.

All three clients use `AGENTS.md`. Claude Code requires at least 2.1.277 and an
available native AGENTS loader. A version check alone is not a live loading
proof: start a fresh session and verify a harmless instruction from the file.
The installer never creates a CLAUDE adapter to compensate for missing support.

Native client invocation remains available without Jev:

```bash
jevcodex --no-route "Inspect the project and summarize its next task"
jevclaude --no-route "Inspect the project and summarize its next task"
jevcursor --no-route "Inspect the project and summarize its next task"
```

Nested independent repositories require explicit `--context relative/path`
entries at installation. An unapproved nested repository cannot inherit this
project's runtime merely because it lives below it.

To preview and remove managed installation files, run the installer with
`--uninstall --dry-run`, then `--uninstall`. Local edits to managed files stop
removal. Task state and credentials are retained. A protected
`.datarim-uninstalled/` recovery bundle is retained for inspection.

Updates compare shared files against their initial contents before publishing.
Concurrent edits stop the transaction. If rollback cannot restore a shared file,
the installer retains a private `.datarim-recovery-<id>/` bundle and prints its
path. Its `rollback-files.json` contains the exact pre-update contents. Preserve
that bundle until the reported files have been reconciled; it may contain private
client configuration and must never be committed.

Next: [Initialize with Jev](initialize-datarim-with-jev.md),
[configuration](../how-to/configure-and-use-jev.md), and
[CLI reference](../reference/jev-cli.md).
