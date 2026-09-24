# Installing Datarim

**AI agents: run `./install.sh --project <path>` first and relay the questions it prints to the user; rerun with their answers and the token the installer printed. It refuses a fresh install without them.** The steps are in
[If you are an AI agent](#if-you-are-an-ai-agent-asked-to-install-datarim).

This is the single install guide for Datarim and its optional companion, Jev. It is
written for people and for AI agents alike. Every command, path and variable here
was taken from the installer code (`scripts/project_install.py`,
`scripts/jev_host_install.py`, `scripts/jev.py`), not from older documents.

- **Datarim** is installed into **one project at a time**. It copies a pinned
  snapshot of the framework into `<project>/.datarim-runtime/`, writes the `/dr-*`
  commands where Claude Code, Codex and Cursor find them, and hides everything it
  writes from `git status`. It does not touch your home directory, your shell
  startup files, `AGENTS.md` or `.gitignore`, and creates `CLAUDE.md` only when
  you ask for it (`--claude-import`, see [Other install options](#other-install-options)).
- **Jev** is optional. It adds a deterministic safety floor (a hook that refuses
  destructive shell commands, no key or network needed) and, with an API key,
  model-tier routing advice. It can be installed per project or once for the
  whole host.

---

## If you are an AI agent asked to install Datarim

Follow these steps in order. Do not improvise other install methods.

1. **Step 1: run `./install.sh --project <path>` with no answer flags. Ask the user nothing before that run; the installer prints the questions.** Then read this whole file before running anything else. Fetch it raw —
   `curl -fsSL https://raw.githubusercontent.com/Arcanada-one/datarim/main/INSTALL.md`
   — or read `INSTALL.md` in a clone; a summarizing web fetch drops most of it.
   To read the installer source, read it in the `SOURCE` clone; do not
   download copies of it elsewhere.
   Do not choose the answers yourself. The installer enforces it: a fresh
   install run without a terminal prints the questions, the flag for each
   answer and a one-time answers token, exits with code 2 and writes nothing
   to the project — `--dry-run` included. It proceeds only when rerun with
   the user's answers **and** that token (`--answers`), within an hour.
2. **Establish the two paths.**
   - `PROJECT` — the absolute path of the project the user wants Datarim in
     (usually the current working directory). It must be an existing directory
     and must not be the home directory, a system directory, or the Datarim
     source checkout itself.
   - `SOURCE` — where the Datarim repository is cloned. It must be **outside**
     `PROJECT` (the installer refuses a source inside the project) and it must
     **last**: updates and uninstall run from it later. Suggest `~/src/datarim`
     unless the user names another place; never `/tmp` or a scratch directory.
3. **Run `./install.sh --project "$PROJECT"` and relay the questions it prints**
   to the user, word for word, with their defaults; wait for the answers. They
   are the questions below. Accept the defaults only if the user says so
   ("defaults", "just install it").

   | # | Question | Default |
   |---|---|---|
   | 1 | Install Jev? **none** / **project** (this project only) / **host** (every project of this user on this machine) | none |
   | 2 | Which clients do you use: Claude Code, Codex, Cursor? Pass one `--client` per client (or a comma list); the project install then writes the commands, and with `--with-jev` the hooks, only for those. The same answer gives host Jev its `--client` options and decides which client `jev doctor --agent=` checks. | the ones installed on the machine |
   | 2a | If Claude Code is one of them and the project has an `AGENTS.md`: link `CLAUDE.md` to it (`--claude-import`)? Claude Code reads `CLAUDE.md`, not `AGENTS.md`. Only offered when the project has no `CLAUDE.md`. | yes, when there is no `CLAUDE.md` |
   | 3 | Should the `jev*` launchers (every install has them) start clients **without permission prompts**? Answered with `--permissions ask` or `--permissions full` (required on a fresh install; `jev permissions` changes it later). Starting a client directly is not affected. | no (`ask`) |
   | 4 | Create empty task files `datarim/tasks.md` and `datarim/backlog.md` now (`--init`)? | yes |
   | 5 | Expose every framework skill to the clients' automatic discovery (`--expose-skills`)? It adds their descriptions to every session. | no |
   | 6 | Install the latest release tag, or `main`? | latest release tag |

   Also check, without asking, whether `PROJECT` contains nested git repositories
   (`find "$PROJECT" -mindepth 2 -name .git -not -path '*/node_modules/*'`). If it
   does and the user wants Datarim to work inside them, add one
   `--context <relative/path>` per repository.
4. **Rerun the installer** with the flags the answers give
   ([Answers and flags](#answers-and-flags)) and `--answers` followed by the
   token the installer printed. The token is valid for an hour, for that
   project only, and is used up by a successful install; if it expired, run the
   installer once more to get a new one.
   Never write an API key yourself and never ask the user to paste a key into
   the chat.
5. **Verify** with [Step 5](#step-5--verify). Every check has an expected result.
6. **Report to the user**, in this shape:
   - installed: Datarim version and commit (from `.datarim-runtime/installation.json`
     → `source_sha`), Jev scope (none / project / host), permission mode (`ask` or
     `full`, as set with `jev permissions`), options used;
   - where things live: `.datarim-runtime/` (framework), `datarim/` (task state),
     Jev config file path (see the [table](#configuration-and-secrets));
   - **where to put the Jev API key** (exact file path; open it in an editor, one
     line, file stays mode `0600`), then run `jev doctor --api`;
   - never put the key or any `JEV_*` / `DATARIM_*` variable in shell startup
     files (`.zshrc`, `.bashrc`); set them per shell or per launch;
   - Codex only: the two approvals Codex will ask for (see
     [Codex hook trust](#codex-runs-hooks-only-after-you-trust-them));
   - how to update: `cd <SOURCE> && git pull` (or check out the new tag), then
     `./update.sh --project <PROJECT>`; the install choices are remembered, so no flags are needed;
   - every line the installer printed after "Include these lines in your report
     to the user:", copied as printed;
   - next step: open the client in the project and run `/dr-help` (Claude Code),
     or ask Codex or Cursor to run the `dr-help` skill.

---

## Step 1 — Prerequisites

- Python 3.10 or newer, and git.
- At least one installed and signed-in agent client: Claude Code (`claude`),
  Codex CLI (`codex`) or Cursor CLI (`cursor-agent` or `agent`). Datarim does
  not create client accounts and does not read model-provider keys; each client
  authenticates itself.
- The project directory. A git repository is recommended: that is what lets the
  installer hide its files through `.git/info/exclude`.
- For Jev routing advice only: a Jev API key. Keys are issued by the Jev API
  provider, TypeSafe (`api.typesafe.ai`). You need **one key per computer**,
  shared by every client on it (Claude Code, Codex and Cursor use the same key
  file). Without a key Jev still runs its local safety floor; only the routing
  advice is missing.

## Step 2 — Get the source

```sh
git clone https://github.com/Arcanada-one/datarim.git ~/src/datarim
cd ~/src/datarim
git checkout "$(git describe --tags --abbrev=0 --match 'v*')"   # latest release tag
```

Keep this checkout: `update.sh` and `--uninstall` run from it later, so put it
somewhere lasting such as `~/src/datarim`, never in `/tmp`. Staying on `main` is
also supported. Whatever you check out, the installed
commit is recorded in `<project>/.datarim-runtime/installation.json`
(`source_sha`), so you can always tell what a project runs. To pin a project to
a release, check out that tag (`git checkout vX.Y.Z`) before installing or
updating; tags are the stable way to pin, commit hashes are not quoted in these
docs. Host Jev refuses to install from a checkout with uncommitted changes.

## Step 3 — Install

Set the project path once (absolute):

```sh
PROJECT=/absolute/path/to/project
```

Run the installer with only the project path:

```sh
./install.sh --project "$PROJECT"   # prints the questions to ask and the flags for each answer
```

At a terminal it asks each question in turn; press Enter for the default.
Without a terminal (an agent, a script) it installs nothing on a fresh project:
it prints the questions, the flag for each answer and a one-time answers
token, and exits with code `2`. Ask the user the questions, wait for the
answers, then run it again with the flags the answers give and `--answers`
with the printed token (add `--dry-run` first to see the plan). Never pick the
answers yourself. Jev's safety floor works without any key; a missing key is
not a reason to answer "no Jev".

### Answers and flags

| Answer | Flag |
|---|---|
| Jev: none | `--without-jev` |
| Jev: project | `--with-jev`. Hooks go into this project only, for the chosen clients (`.claude/settings.local.json`, `.codex/hooks.json`, `.cursor/hooks.json`), and an empty key file is created at `config/credentials/jev/api-key` (mode `0600`). Not on a machine that already has host Jev: both sets of hooks would run. |
| Jev: host | `--with-jev --host-jev`, after the host step below |
| Clients | `--client` with the chosen ones, e.g. `--client claude,codex`; required on a fresh install |
| Link `CLAUDE.md` to `AGENTS.md` (Claude Code) | `--claude-import` |
| Create task files now | `--init` |
| Every skill in every session | `--expose-skills` |
| Nested repositories to include | `--context <relative/path>`, once per repository |
| Permission mode | `--permissions ask` or `--permissions full`; required on a fresh install, kept on update |
| Release tag or `main` | before the install, in the source checkout: `git checkout <tag>` or `git checkout main` |

Only when the user said "defaults": `--without-jev`, `--client` with the clients
installed on the machine, `--init` and `--permissions ask`, plus
`--claude-import` when Claude Code is one of them and the project has an
`AGENTS.md` but no `CLAUDE.md`.

### Only if the user chose host Jev: install host Jev first

Host Jev is installed once per user and applies to every directory that user
opens. It writes `~/.config/jev/`, `~/.local/share/jev/`, `~/.local/state/jev/`,
the launchers `~/.local/bin/{jev,jevclaude,jevcodex,jevcursor}` (that directory
must be on `PATH`), and merges its hooks into each chosen client's user config
(`~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json`),
keeping every existing hook. Skip this step for any other Jev answer.

```sh
# one --client per client the user chose; one --datarim-project per project that may use Datarim
python3 scripts/jev_host_install.py --client claude --client codex --client cursor \
  --datarim-project "$PROJECT" --dry-run
python3 scripts/jev_host_install.py --client claude --client codex --client cursor \
  --datarim-project "$PROJECT"
```

Then run the project install with `--with-jev --host-jev` and the other flags
from the answers. `--datarim-project` **replaces** the host's list of Datarim
projects; when you add a project later, pass every project again. The key file
is `~/.config/jev/credentials/api-key`.

### Scripted installs (CI)

There is no switch that skips the answers token. An unattended pipeline that
provisions a project with fixed, reviewed answers runs the installer twice:
the first run refuses and prints the answers token on its rerun line, the
second passes that token with the same answers. Replace `<flags>` with the
reviewed answer flags, identical in both runs:

```sh
out="$(./install.sh --project "$PROJECT" <flags> 2>&1)"
token="$(printf '%s\n' "$out" | sed -n 's/.*--answers \([0-9a-f][0-9a-f]*\) .*/\1/p' | tail -n 1)"
[ -n "$token" ] || { printf '%s\n' "$out" >&2; exit 1; }
./install.sh --project "$PROJECT" --answers "$token" <flags>
```

An AI agent installing Datarim for a person does not do this: it relays the
questions the first run prints to the person and uses their answers. Each
refusal issues a new token that replaces any earlier one.

### Option D — Jev without Datarim

See [Use Jev on its own](documentation/how-to/jev-without-datarim.md): the same
`scripts/jev_host_install.py`, without `--datarim-project`, and no project
install.

### Other install options

| Option | Effect |
|---|---|
| `--client <name>` | `claude`, `codex`, `cursor` or `all`; repeat it or give a comma list. Only these clients get command files and (with `--with-jev`) hooks. Required on a fresh install. Kept across updates; a client you leave out on an update loses its command files and Jev hooks. |
| `--claude-import` | Creates `CLAUDE.md` as a symlink to the project's `AGENTS.md`, so Claude Code (which reads `CLAUDE.md`, not `AGENTS.md`) loads your project rules. Only when no `CLAUDE.md` exists: an existing file or link is never changed. Kept across updates; `--no-claude-import` or uninstall removes only a link the install made. A symlink rather than an `@AGENTS.md` import line, because the import was observed to be ignored in sessions started in a subdirectory. |
| `--init` | Creates `datarim/tasks.md` and `datarim/backlog.md` if missing. Existing files are kept. |
| `--expose-skills` | Also writes every framework skill into `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`. Their descriptions load into every session. Kept across updates once set. |
| `--context <relative/path>` | Lets an existing nested git repository use this installation. Repeat per repository. Without it, a nested repository is refused. Kept across updates; given again, it replaces the list; `--no-context` clears it. |
| `--without-jev`, `--no-host-jev` | `--without-jev` is the "no Jev" answer a fresh install requires (it or `--with-jev`). On update they turn off a recorded `--with-jev` or `--host-jev`; `--without-jev` then withdraws the project's Jev hooks and `jev-config.json`; the key file stays. |
| `--dry-run` | Prints the plan as JSON; writes nothing. On a fresh install it needs the Jev answer and `--client` too. |
| `--uninstall` | See [Uninstall](#uninstall). |

### What the project install writes

| Path | Content | In `git status` |
|---|---|---|
| `.datarim-runtime/` | the framework snapshot, `installation.json`, `activate.sh`, `bin/jev*` | no |
| `.claude/commands/dr-*.md` | the commands for Claude Code (with `--client claude`, or no `--client`) | no |
| `.agents/skills/dr-*/`, `.cursor/skills/dr-*/` | the same commands as skills for Codex and Cursor (each only when selected) | no |
| `CLAUDE.md` → `AGENTS.md` (with `--claude-import`, when no `CLAUDE.md` exists) | a symlink | no |
| `datarim/` (with `--init`) | this project's task state | no |
| `config/credentials/jev/api-key` (with `--with-jev`) | empty key file, mode `0600` | no |
| `.claude/settings.local.json`, `.codex/hooks.json`, `.cursor/hooks.json` (with `--with-jev`, not `--host-jev`) | Jev hook entries, merged into any existing file | no, if the install created the file |
| `.git/info/exclude` | the rules that hide all of the above | never committed |

A client config file the project already tracked in git stays tracked; the
install only adds Jev entries to it.

## Step 4 — Keys, settings and permission mode

### The Jev API key

Open the key file for your install in an editor, paste the key on one line,
save. Do not `echo` or `printf` the key into the file: the command lands in your
shell history. A `--with-jev` install prints the exact key file path. The file already exists with mode `0600`; keep it that way.

| Install | Key file |
|---|---|
| Project Jev (answer "project") | `<project>/config/credentials/jev/api-key` |
| Host Jev (answer "host", or Jev without Datarim) | `~/.config/jev/credentials/api-key` |

With host Jev the project's own key file stays empty and unread; that is
correct. Never put the key in a shell command (it lands in history), a commit, a
settings file or a chat. `export TYPESAFE_API_KEY=...` does not work: the
launchers and hooks remove that variable and read only the file. One key per
computer, shared by all its clients; use a different key on each computer.

### Permission mode (Jev launchers only)

```sh
jev permissions          # show the current mode
jev permissions full     # jev* launchers start clients without permission prompts
jev permissions ask      # back to the client's own prompts (default)
```

`full` adds `--dangerously-skip-permissions` (Claude Code),
`--dangerously-bypass-approvals-and-sandbox` (Codex) or `--force --approve-mcps`
(Cursor) to launches through `jev`, `jevclaude`, `jevcodex`, `jevcursor`, unless
you pass your own permission option. It is stored per project (project
install) or per host (host Jev). The Jev safety floor still runs in `full`
mode. Starting `claude`, `codex` or `cursor-agent` directly is not affected.

### Configuration and secrets

Nothing here is committed: the project paths are hidden by `.git/info/exclude`,
the host paths live in your home directory.

The environment variables below are set **per shell or per launch**, never in
`.zshrc`, `.bashrc` or another startup file. There they would apply to every
session on the machine: `JEV_PERMISSIONS=full` in a startup file, for example,
turns off permission prompts for every `jev*` launch, whatever the stored mode
says. Persistent choices have their own switches: `jev permissions`, `jev on` /
`jev off`, and the settings file.

| Setting | Where | Read by | Required | Default |
|---|---|---|---|---|
| Jev API key (project Jev) | file `<project>/config/credentials/jev/api-key`, mode `0600` | `plugins/dr-jev-control/scripts/project_state.py` `read_key()`, via `TYPESAFE_API_KEY_FILE` set in `scripts/project_scope.py` `activate()` and `scripts/jev_hook.py` `environment()` | only for routing advice | created empty |
| Jev API key (host Jev) | file `~/.config/jev/credentials/api-key`, mode `0600` | same reader; path from `host-installation.json` (`scripts/jev_host_install.py`) | only for routing advice | created empty |
| Jev settings (project) | `<project>/.datarim-runtime/jev-config.json`: endpoint, timeouts, retries, routing modes, hook switches, telemetry | `plugins/dr-jev-control/scripts/route.py` `load_cfg()` via `DATARIM_JEV_CONFIG` | no | copied from `plugins/dr-jev-control/config/jev-control.json` |
| Jev settings (host) | `~/.config/jev/config.json`, including `datarim_projects` (projects allowed to use Datarim) | `scripts/jev_hook.py` `environment()` | no | same defaults; `api.base_url` must stay `https://api.typesafe.ai/v1/systemone` or host install and host requests refuse |
| On/off switch | `jev off` / `jev on`: file `DISABLED` in `.datarim-runtime/state/jev/` or `~/.local/state/jev/` | `project_state.py` `disabled_reason()` | no | on |
| Permission mode | `jev permissions full\|ask`: file `FULL_PERMISSIONS` in the same state directory; env `JEV_PERMISSIONS=full\|ask` overrides it for one launch | `scripts/jev.py` `full_permissions()` | no | `ask` |
| Disable Jev advice for a shell | env `JEV_DISABLE=1` or `DATARIM_JEV_DISABLE=1` (the safety floor still runs) | `project_state.py` `disabled_reason()` | no | unset |
| Codex model per Jev tier | env `DATARIM_CODEX_MODEL_HAIKU`, `_SONNET`, `_OPUS` | `scripts/jev.py`, `plugins/dr-jev-control/scripts/runtimes.py` | no | Codex account default, tier mapped to effort |
| Cursor model per Jev tier | env `DATARIM_CURSOR_MODEL_HAIKU`, `_SONNET`, `_OPUS` | same | no | Cursor default model |
| Client executable | env `CLAUDE_BIN`, `CODEX_BIN`, `CURSOR_BIN` | `scripts/jev.py` `binary()` | no | `claude`, `codex`, `cursor-agent` (or `agent`) on `PATH` |
| Codex auto re-trust | env `JEV_NO_AUTO_TRUST=1` stops `jevcodex` (host Jev) from re-granting Codex trust to Jev's own hooks | `scripts/jev.py` | no | unset |
| Execution-host map | env `DATARIM_EXEC_HOSTS_MAP`, a YAML map of which machine may run tasks for a workspace | `/dr-init`, `/dr-quick`, `/dr-next` via `dev-tools/lib/execution-host.sh` | no | `$HOME/.claude/local/config/execution-hosts.yml`; absent map means the check is skipped |

Set by the entry points, never by hand: `DATARIM_RUNTIME` (by
`source .datarim-runtime/activate.sh`, together with `PATH`), and
`DATARIM_ROOT`, `DATARIM_PROJECT_ROOT`, `DATARIM_JEV_CONFIG`,
`DATARIM_JEV_HOME`, `DATARIM_JEV_STATE`, `TYPESAFE_API_KEY_FILE`,
`JEV_STATE_DIR`, `JEV_HOST_STATE` (by `jev*` and the hooks, from the
installation they belong to). An exported `TYPESAFE_API_KEY` is removed by the
launchers and hooks; keep the key in the file.

Model-provider keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_AI_API_KEY`,
`DEEPSEEK_API_KEY`) are optional and not read by the installer, Datarim's
commands or Jev; `config/model-tiers.yaml` only names them as the convention an
external adapter would use. Your clients keep their own sign-in. The
optional plugins and CLI read their own variables (`DR_ORCH_*`, `DR_FLEET_*`,
`DATARIM_CLI_*`); they are not needed to install, see each plugin's `README.md`
under `plugins/` and [the CLI reference](documentation/reference/cli.md).

## Step 5 — Verify

```sh
cd "$PROJECT"
git status --short                       # expect: nothing from Datarim
source .datarim-runtime/activate.sh      # current shell only
jev doctor --agent=claude                # or --agent=codex / --agent=cursor
```

Expected `jev doctor` output (JSON), exit code `0`:

- `"scope": "project"` (or `"host"` with `--host-jev`), `"datarim_enabled": true`;
- `"findings": []` — a finding names what is missing (for example
  `claude: executable missing`, or `cursor: Jev hook file missing (...)` when a
  selected client's hook file or entry was removed) and makes the exit code
  `1`. Without `--agent`, doctor checks all three clients, so a client you do
  not use becomes a finding;
- `"hook_clients"` — the clients whose Jev hooks this install registered;
- `"config_path"` — the Jev settings file in use (`.datarim-runtime/jev-config.json`,
  or `~/.config/jev/config.json` with host Jev); `null` without Jev. The
  plugin's `config/jev-control.json` is only the template the installer copies;
- `"native_agents_live"` — per client, `"state": "live"` with a delivery count
  and the last delivery time once the ledger holds a `hook_delivery` record
  from that client; `not_measured` (with a reason) until the client has run a
  hook;
- `"key_ready": false` until you add a key (true means the file is non-empty,
  not that the key is valid);
- `"api": "not_measured"` — offline doctor makes no network call; this is
  neither a pass nor a failure;
- `"source_sha"` — the commit you installed.

After adding a Jev key:

```sh
jev doctor --api
```

Expected: exit code `0` and an `"api"` block containing
`"api": {"ok": true, "model": "...", ...}`. A missing key gives
`"reason": "key missing"` and exit code `1`.

Then open the client in the project:

- Claude Code: run `/dr-help`.
- Codex or Cursor: ask the agent to run the `dr-help` skill.

The answer comes from `.datarim-runtime/commands/dr-help.md`. Start work with
`/dr-init "<task description>"`; the [getting-started
tutorial](documentation/tutorials/getting-started.md) continues from here.

### Checks that need no key

The safety floor, with Jev installed. Run in the project; the destructive
command is only text inside the JSON payload, nothing is executed:

```sh
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"%s","session_id":"check"}' "$PWD" \
  | python3 .datarim-runtime/scripts/jev_hook.py claude PreToolUse      # project Jev
# host Jev: pipe the same payload into  ~/.local/share/jev/bin/jev-hook claude PreToolUse
```

Expected: `{"hookSpecificOutput": {..., "permissionDecision": "deny",
"permissionDecisionReason": "Jev deterministic safety floor: recursive delete of
a protected path"}}`.

| Question | Check | Expected |
|---|---|---|
| Do the clients call the hooks? | Use a client for one short session in the project (read a file, run a harmless shell command), then `tail -n 3 .datarim-runtime/state/jev/ledger.jsonl` | `hook_delivery` records naming the client (`"client": "claude"`, `"codex"` or `"cursor"`). Floor denials return before the ledger write and are not recorded. Host Jev keeps its ledgers under `~/.local/state/jev/projects/`. |
| Is Jev installed and scoped correctly? | `jev doctor --agent=<client>` | the fields listed above; after that session `native_agents_live` shows the client as `live` |
| Are the task files well-formed? | `bash .datarim-runtime/scripts/datarim-doctor.sh --root="$PWD"`, or `/dr-doctor` in a client | `OK: datarim/ structure compliant` |

`jev doctor` answers for Jev (clients, hook registrations, key file, scope,
Codex trust, hook deliveries); `datarim-doctor.sh` and `/dr-doctor` answer only for the structure of the
`datarim/` task files.

### Codex runs hooks only after you trust them

With Jev and Codex, the first Codex session asks twice: to trust the working
directory, then `Hooks need review` → choose **Trust all and continue**.
Declining is silent: Codex still lists the hooks as active but never runs them.

`jev doctor --agent=codex` reports `codex_hook_trust` as `trusted`,
`untrusted` or `not_measured`, from the grants Codex stores in
`~/.codex/config.toml`:

- Host Jev: for the hooks in `~/.codex/hooks.json`. If another tool rewrote
  that file and moved the Jev entries, run `jev trust` to re-grant trust to
  Jev's own hooks only (`jevcodex` does this automatically unless
  `JEV_NO_AUTO_TRUST=1`).
- Project Jev: for the hooks in `<project>/.codex/hooks.json`. `jev trust`,
  run inside the project, re-grants trust to exactly those hooks; `jevcodex`
  does not do it automatically for a project install. `not_measured` with the
  reason `no Codex config.toml` means Codex has not written any trust yet.

An install that changes the hook command (for example the interpreter path)
makes Codex report the hooks as changed; `jev trust` or the Codex prompt
approves them again.

Details: [Codex needs two approvals](documentation/how-to/jev-without-datarim.md#codex-needs-two-approvals-in-its-own-ui).

---

## Update

```sh
cd ~/src/datarim
git fetch --tags origin
git checkout "$(git describe --tags --abbrev=0 --match 'v*' origin/main)"   # or: git checkout main && git pull
./update.sh --project "$PROJECT"   # the choices you installed with are remembered
```

`update.sh` runs the same installer, as one transaction: it checks every file
first, refuses to overwrite anything you edited, and rolls back on failure.

**Your install choices are remembered.** `--with-jev`, `--host-jev`,
`--context`, `--client`, `--expose-skills` and `--claude-import` are recorded
in `.datarim-runtime/installation.json`, so a plain `update.sh --project`
keeps them. Pass an option only to change it: `--without-jev` withdraws the
project's Jev hooks and `jev-config.json` (the key file stays),
`--no-host-jev` returns to project hooks, `--no-context` withdraws nested
repositories, `--client` sets a new client list, `--no-claude-import` removes
the `CLAUDE.md` link. Installs made before this release have no recorded
client list and keep all three. The previous runtime is kept in
`.datarim-runtime-previous/`, older ones in `.datarim-runtime-backups/`.

Kept across an update: `datarim/`, `config/credentials/`,
`.datarim-runtime/state/` (ledger, on/off and permission switches), and
`.datarim-runtime/jev-config.json` while Jev stays on. Anything else
you put inside `.datarim-runtime/` is replaced. That includes the plugin links
under `.datarim-runtime/local/`: if you enabled plugins with `/dr-plugin`, run
`/dr-plugin sync` after the update to recreate them from the kept list in
`datarim/enabled-plugins.md`.

Host Jev: rerun `scripts/jev_host_install.py` with the same `--client` and
`--datarim-project` options from the updated checkout. Codex keeps its trust:
the hook command names a stable entry point, not the release.

### Coming from Datarim 2.x

2.x installed globally (`./install.sh --with-claude`, links into `~/.claude/`,
`~/.codex/`, `~/.cursor/`). Those flags no longer exist. Remove only the links
under `~/.claude/{agents,skills,commands,templates,scripts,tests,dev-tools}` (and
the Codex and Cursor equivalents) that resolve into your Datarim checkout, then
install per project. A project installed before 3.0 had a block appended to its
`AGENTS.md` and rules appended to `.gitignore`; the next install or update
removes both and leaves the rest of those files alone.

## Uninstall

```sh
~/src/datarim/install.sh --project "$PROJECT" --uninstall --dry-run
~/src/datarim/install.sh --project "$PROJECT" --uninstall
```

This restores the files the install changed to their pre-install content,
removes the command files and hook entries it added, and moves the runtime to
`.datarim-uninstalled/`. Task state (`datarim/`), keys (`config/credentials/`)
and runtime backups stay, still hidden from git; delete them yourself when you
no longer need them. A second uninstall refuses while `.datarim-uninstalled/`
exists. Files you edited after install stop the uninstall until you reconcile
them.

Host Jev has no uninstaller. `jev off` stops all Jev API calls on the host. To
remove it, delete the Jev entries (commands naming
`~/.local/share/jev/bin/jev-hook`) from the client configs, then
`~/.local/bin/{jev,jevclaude,jevcodex,jevcursor}`, `~/.local/share/jev/`,
`~/.config/jev/` (holds the key) and `~/.local/state/jev/` (holds install
backups).

---

## Troubleshooting

| Message or symptom | Cause and fix |
|---|---|
| `Choose a consumer project, not home, a system directory, or product source` | `--project` is the home directory, a system directory, the Datarim checkout, or a directory that contains the checkout. Clone Datarim outside the project. |
| `Unmanaged or locally modified file: <path>` | A file the install would write already exists with other content (or you edited a managed file). Move or reconcile it, then rerun. |
| `Existing unmanaged .datarim-runtime; refusing overwrite` | A `.datarim-runtime/` without `installation.json`, for example a manual copy. Move it away. |
| `Another installation transaction owns this project` | Another install or update is running on the project. Wait for it. |
| `STOP. Nothing was installed.` (exit code `2`) | A fresh install without a terminal and without every answer (Jev, `--client`, `--permissions`) plus a valid answers token, with or without `--dry-run`. Ask the user the questions it prints, wait for the answers, then rerun with their flags and `--answers` with the token it printed (valid for an hour). Updates keep the recorded answers and never ask. |
| `--host-jev requires --with-jev` | Pass both. |
| `Install host Jev before selecting host ownership` | `--host-jev` without host Jev. Run `scripts/jev_host_install.py` first ([host Jev step](#only-if-the-user-chose-host-jev-install-host-jev-first)). |
| `jev install: Commit and verify the source revision before host installation` | Host Jev needs a clean git checkout. Discard local changes or check out a tag; a release tarball without `.git` cannot install host Jev. |
| `jev install: Host Jev requires the pinned provider endpoint` | `~/.config/jev/config.json` has another `api.base_url`. Restore `https://api.typesafe.ai/v1/systemone`. |
| `jev: No project-local Datarim installation in this directory` | You are outside the project (or the project has no install). `cd` into it. |
| `jev: Nested repository is not an approved project context` | Reinstall with `--context <relative/path>` for that repository. |
| `jev doctor` exits `1` with `<client>: executable missing` | That client is not installed or not on `PATH`. Use `--agent=` for the clients you have, or set `CLAUDE_BIN` / `CODEX_BIN` / `CURSOR_BIN`. |
| `claude: native AGENTS requires >=2.1.277` | Only affects loading your project's `AGENTS.md` natively; `/dr-*` commands do not depend on it. Update Claude Code to clear the finding. Where Claude Code still does not load `AGENTS.md`, update with `--claude-import`. |
| `<client>: Jev hook file missing` or `Jev hook not registered for <event>` | The hook file or entry was deleted or rewritten by hand or by another tool. Run `update.sh --project "$PROJECT"` to register it again. |
| Jev hooks run twice | Host Jev and a project `--with-jev` install without `--host-jev`. Update the project with `--with-jev --host-jev`. |
| Codex hooks never run | Trust was not granted; see [Codex hook trust](#codex-runs-hooks-only-after-you-trust-them). |
| Jev hooks disappeared after an update | Before this release an update without `--with-jev` withdrew them. Rerun the update once with `--with-jev`; it is remembered from then on. |

More: [configure and use Jev](documentation/how-to/configure-and-use-jev.md),
[host Jev with project Datarim](documentation/how-to/host-jev-with-project-datarim.md),
[Jev CLI reference](documentation/reference/jev-cli.md),
[multi-runtime details](documentation/how-to/multi-runtime.md),
[release verification](documentation/how-to/release-verification.md).
