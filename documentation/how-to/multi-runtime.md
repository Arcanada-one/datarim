# How to use Datarim with Claude Code, Codex and Cursor

One install serves all three clients in the same project. Datarim 3.0 installs
into the project, not into `~/.claude`, `~/.codex` or `~/.cursor`, and each
client finds the `/dr-*` commands through its own project-local directory.

## Install

Install once per project as described in [INSTALL.md](../../INSTALL.md). There
is no option to choose clients: every install writes the command files for all
three, and `--with-jev` registers hooks for all three. A client you do not use
simply never reads its files.

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

`--with-jev` also registers Jev's hooks for all three clients in the project;
`--with-jev --host-jev` reuses a Jev you installed for the whole machine instead
(see [INSTALL.md](../../INSTALL.md), options B and C). Codex runs a hook only
after you approve it in its TUI — see
[the Jev control plane guide](claude-code-jev-control-plane.md).

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
