# Install Human Outcome Reporting without Datarim

Use the reporting skill in ordinary Claude Code, Codex and Cursor sessions. This
installation copies one skill and enables a communication preference. It does
not install Datarim commands, agents, a task directory, orchestration or project
rules. [Datarim project installation](../../INSTALL.md) remains a separate choice.

## Install from the release

Download the `human-outcome-reporting` standalone ZIP and its SHA-256 checksum
from the [latest GitHub release](https://github.com/Arcanada-one/datarim/releases/latest).
Verify the checksum before extracting. The extracted directory contains
`install.py`, `human-outcome-reporting/`, and this guide as `INSTALL.md`.

```bash
python3 install.py install --dry-run
python3 install.py install
python3 install.py check
```

Python 3.9 or later on macOS or Linux is required; no third-party Python modules are needed. The optional bundled report validation
tools require Python 3.10 or later. From a
framework source checkout, use this equivalent command:

```bash
python3 scripts/human_reporting_install.py install
```

Choose clients with `--agents claude,codex,cursor` or a comma-separated subset.
Use `--home /path/to/account/home` only for a specifically authorized account;
remote and local accounts have independent installation scopes. `--source` takes
the skill directory containing `SKILL.md`. Save a non-secret operation receipt
with `--receipt /path/to/reporting-install.json`.

## What is installed

| Client | Skill directory | Persistent reporting preference |
| --- | --- | --- |
| Claude Code | `~/.claude/skills/human-outcome-reporting/` | `~/.claude/output-styles/human-outcome-reporting.md`, selected through `outputStyle` in user `settings.json`; coding instructions are preserved |
| Codex | `~/.agents/skills/human-outcome-reporting/` | A marked reporting-only section in `~/.codex/AGENTS.md`; a non-empty existing `AGENTS.override.md` receives the section instead |
| Cursor | `~/.cursor/skills/human-outcome-reporting/` | A user `sessionStart` hook in `~/.cursor/hooks.json` injects the reporting preference and installed skill path |

The installer merges existing settings and hooks under an account-level transaction lock. It never creates `CLAUDE.md`,
changes permissions, replaces safety hooks, or activates a framework globally.
An installation state with protected before-images is saved in
`~/.local/state/datarim-human-reporting/` (directory mode 0700, files mode 0600).
These backups may contain existing private client settings; keep them local.

The mechanisms are documented by [Claude output styles](https://code.claude.com/docs/en/output-styles),
[Codex instruction discovery](https://developers.openai.com/codex/guides/agents-md),
and [Cursor user hooks](https://cursor.com/docs/hooks). Each client must support
its native feature; client version alone is not a behavior test. Skill discovery
is separate from guaranteed instruction compliance.

Restart existing sessions after installing or updating. In Cursor, create a new
conversation: resuming an old chat does not rerun its session-start hook. Claude project settings
can override the user output style. Codex project instructions can override user
preferences. Cursor local user hooks and skills do not automatically propagate
to cloud workers or another SSH account. Use an authorized installation in each
remote account, or project/team configuration on a worker. User preferences are
instructions, not a deterministic semantic gate.

## Check a real session

`check` verifies installed file hashes and reports behavior as `not_measured`.
To test behavior, start a new session in a disposable directory without Datarim.
Ask the client to explain a task whose files are complete but whose production
check has not run. Verify that it explains the usable result and explicitly
states the production uncertainty. Request a clearer explanation and verify that
it reads or explains existing evidence without resuming edits or deployment.
Keep the prompt, native client version, answer, and any tool calls as evidence.
Then repeat in an explicitly enabled temporary Datarim project using
[the framework installation guide](../../INSTALL.md). A structural validator or
simulated fixture does not prove that a person understood the report.

## Update and reverse

Re-run `install` from the verified newer release. The update is idempotent and
removes stale files previously owned by this installer only when unchanged.
Symlink destinations, malformed shared settings and modified owned files cause
a preflight refusal before any installation writes. Reconcile the named file
with its owner, preserve edits, and retry. Interrupted installation leaves a
protected `pending.json` journal; reconcile its before-images before retrying.
Never print that journal into an external log.

```bash
python3 install.py uninstall --dry-run
python3 install.py uninstall
```

Uninstall restores previous skill files and the prior Claude output style,
removes only its Codex section and Cursor hook, and preserves later unrelated
settings and rules. If someone changed an owned file or selected another Claude
style, uninstall refuses to overwrite it. The installer does not remove empty
client directories. Keep operation receipts separately from the package so they
remain available after an update or uninstall.

Inside Datarim, [Human Outcome Reporting](../../skills/human-outcome-reporting/SKILL.md)
is loaded by the existing command and agent paths. A host installation and a
project runtime follow the same communication policy; neither grants new
execution permissions or changes acceptance criteria.
