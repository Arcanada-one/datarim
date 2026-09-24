# How to use Datarim with Claude Code, Codex and Cursor

One install serves all three clients in the same project, or the ones you pick. Datarim 3.0 installs
into the project, not into `~/.claude`, `~/.codex` or `~/.cursor`, and each
client finds the `/dr-*` commands through its own project-local directory.

## Install

Install once per project as described in [INSTALL.md](../../INSTALL.md). By
default every install writes the command files for all three clients, and
`--with-jev` registers hooks for all three. `--client` limits both to the
clients you name (`--client claude --client codex`, or `--client claude,codex`).
The choice is recorded in `.datarim-runtime/installation.json` and kept by
updates; an update with a shorter list removes the command files and Jev hook
entries of the clients left out (a hook file the install created goes too when
nothing else is in it).

| Client | Where it finds the commands | How you run one |
|---|---|---|
| Claude Code | `.claude/commands/dr-*.md` | `/dr-help`, `/dr-init "…"`, … |
| Codex CLI | `.agents/skills/dr-*/SKILL.md` | ask it to run the `dr-help` skill |
| Cursor | `.cursor/skills/dr-*/SKILL.md` | ask it to run the `dr-help` skill |

Every command file names this project's runtime (`.datarim-runtime/`) and tells
the agent to read the framework rules from there. Nothing is added to
`AGENTS.md` or any other file the client loads on every session, so a session
that never runs a command never loads the framework. All generated paths are
hidden from git through `.git/info/exclude`.

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. `--claude-import` makes your
project rules visible to it by creating `CLAUDE.md` as a symlink to
`AGENTS.md`, only when no `CLAUDE.md` exists; it never changes an existing
file, is kept across updates, and `--no-claude-import` or uninstall removes only
the link it made. The `/dr-*` commands do not need it: each names the runtime
itself.

`--expose-skills` additionally places every framework skill in each client's
automatic discovery. Their descriptions are then part of every session's
context; leave it off unless you want Datarim's skills offered without a
command.

## Verify

```bash
cd /path/to/project
git status --short          # nothing from Datarim
ls .claude/commands .agents/skills .cursor/skills | head
```

Then run `/dr-help` in Claude Code, or ask Codex or Cursor to run the `dr-help`
skill. The answer should come from `.datarim-runtime/commands/dr-help.md`.

## With Jev

`--with-jev` also registers Jev's hooks for the selected clients in the project;
`--with-jev --host-jev` reuses a Jev you installed for the whole machine instead
(see [INSTALL.md, Answers and flags](../../INSTALL.md#answers-and-flags)). Codex runs a hook only
after you approve it in its TUI — see
[the Jev control plane guide](claude-code-jev-control-plane.md). `jev doctor`
reports a finding when a selected client's hook file or entry is missing, the
Codex trust of the project's `.codex/hooks.json`, and, per client, whether the
ledger holds hook deliveries (`native_agents_live`).

## Datarim MCP server (optional)

The installer does not register it. To give an MCP client read access to the
commands, skills and agents of one project's runtime, register it yourself —
for Codex, in `~/.codex/config.toml`:

```toml
[mcp_servers.datarim]
command = "/path/to/project/.datarim-runtime/cli/mcp/datarim-mcp-server.sh"
env = { DATARIM_ROOT = "/path/to/project/.datarim-runtime" }
```

See [the MCP server reference](../reference/mcp-server.md).

## Coming from 2.x

See [INSTALL.md § Coming from Datarim 2.x](../../INSTALL.md#coming-from-datarim-2x).
