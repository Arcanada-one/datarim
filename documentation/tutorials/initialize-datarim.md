# Initialize Datarim in a project

Datarim is installed explicitly inside a consumer project. It does not install
global rules, commands, hooks, or executables. The framework source checkout is
not a task workspace. Python 3.10 or newer is required.

Install with [INSTALL.md](../../INSTALL.md), option A (`--init`, no Jev). This
page explains what that install does and how it behaves afterwards.

The installer copies a runtime into `.datarim-runtime/`, writes the `/dr-*`
commands for each client (`.claude/commands/`, `.agents/skills/dr-*`,
`.cursor/skills/dr-*`), and with `--init` creates missing `datarim/tasks.md` and
`datarim/backlog.md`. Existing task files are preserved. No Jev key is needed
for plain Datarim.

It does **not** edit `AGENTS.md`, `CLAUDE.md` or `.gitignore`. Everything it
generates is hidden from git through the clone-local `.git/info/exclude`, so
`git status` stays clean — which matters in a repository shared with people who
do not use Datarim.

Datarim runs only when you invoke a command. Each command states where this
project's runtime is and tells the agent to read the framework rules from it;
nothing is added to the instructions your agents load on every session. That is
also why Datarim does not depend on whether a client loads `AGENTS.md` — on
Claude Code 2.1.280 with its builtin AGENTS loader inactive, `/dr-help` still
found the runtime and answered from it. Measured on the same host, the starting
context of an empty session grew by 1,579 tokens with Datarim installed (the
list of 28 commands), against 5,329 with the earlier design that also exposed
every framework skill.

`--expose-skills` restores that exposure if you want the framework's skills in
your clients' automatic discovery; it is kept across updates once set.

Native client invocation remains available without Jev:

```bash
jevcodex --no-route "Inspect the project and summarize its next task"
jevclaude --no-route "Inspect the project and summarize its next task"
jevcursor --no-route "Inspect the project and summarize its next task"
```

Nested independent repositories require explicit `--context relative/path`
entries at installation. An unapproved nested repository cannot inherit this
project's runtime merely because it lives below it.

To remove an installation, follow [INSTALL.md § Uninstall](../../INSTALL.md#uninstall). Local edits to managed files stop
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
