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

### Verify the loader before you rely on it

Run this in the installed project. It forbids the file-reading tools, so only
preloaded instructions can answer — reading `AGENTS.md` with a tool proves
nothing about the loader.

```bash
printf '\nProbe token: loader-probe-ok.\n' >> AGENTS.md
claude -p "Without using any tool: state the probe token from your loaded project
instructions, or NOTOKEN." --disallowed-tools "Read,Bash,Glob,Grep"
```

The token means the loader works. `NOTOKEN` means the project's instructions are
not reaching the session, and any workflow that depends on them will behave as if
the file were absent. Remove the probe line afterwards.

Claude Code loads `AGENTS.md` by default only when no `CLAUDE.md`,
`.claude/CLAUDE.md` or `CLAUDE.local.md` exists in the working directory or any
directory above it. A `CLAUDE.local.md` you add for your own uncommitted notes
therefore silences the project's `AGENTS.md`. To load both, set
`instructionFiles` to `claude-md-and-agents-md` under the builtin plugin — and
note the two placement rules that make a wrong attempt look like missing support:

```jsonc
// ~/.claude/settings.json — ignored in project or local settings files
{
  "pluginConfigs": {
    "agents-md@builtin": {
      "options": { "instructionFiles": "claude-md-and-agents-md" }
    }
  }
}
```

**Measured on 2026-09-22, Claude Code 2.1.278 on macOS: this probe returned
`NOTOKEN`**, in a clean temporary project with no ancestor `CLAUDE.md` and no
settings at all — the case where the default is documented to load `AGENTS.md`.
The probe is calibrated: the same file, directory and flags answered correctly
when renamed to `CLAUDE.md`, so the negative is real and not a blind instrument.

The feature is present in the installed build (`AGENTS.md loaded`,
`claude-md-or-agents-md` and `instructionFiles` all appear in the binary), but
`agents-md@builtin` does not appear in `claude plugin list` on this host — not as
disabled, absent. That matches the documented case where a session does not
receive the feature flag that activates the builtin plugin; in such sessions
Claude reads `CLAUDE.md` only and **Project instructions** is missing from
`/config`. The other documented causes were excluded by measurement: the version
is 2.1.277+, no managed settings exist, `disableAllHooks` and
`allowManagedHooksOnly` are unset, the build has been installed for two days
across ~70 sessions, and clearing `DISABLE_TELEMETRY` did not change the result.

So this is **an environment-gated activation, not a missing capability** and not
a property of the version. Before depending on `AGENTS.md`, run the probe on your
own host: if it returns `NOTOKEN`, check `claude plugin list` for
`agents-md@builtin` first. Where the flag is absent the supported fallback is to
import `AGENTS.md` from a `CLAUDE.md` — a one-line import, not a duplicated
instruction file, and not a reason for this installer to generate a CLAUDE
adapter.

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
