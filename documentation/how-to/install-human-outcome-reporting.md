# Install Human Outcome Reporting without Datarim

Use the reporting skill in ordinary Claude Code, Codex and Cursor sessions. This
installation copies one skill and enables a communication preference. It does
not install Datarim commands, agents, a task directory, orchestration or project
rules. [Datarim project installation](../../INSTALL.md) remains a separate choice.

## Install from the release

Download the `human-outcome-reporting` standalone ZIP and its SHA-256 checksum
from the [latest GitHub release](https://github.com/Arcanada-one/datarim/releases/latest).
Verify the checksum, cosign signature bundle and GitHub build provenance before extracting, following the [portable asset verification recipe](https://github.com/Arcanada-one/datarim/blob/main/documentation/how-to/release-verification.md#portable-reporting-assets). The extracted directory contains
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
| Claude Code | `~/.claude/skills/human-outcome-reporting/` | `~/.claude/output-styles/human-outcome-reporting.md`, selected through `outputStyle` in user `settings.json`, and a synchronous `SessionStart` callback; coding instructions are preserved |
| Codex | `~/.agents/skills/human-outcome-reporting/` | A marked reporting-only section in `~/.codex/AGENTS.md` (a non-empty existing `AGENTS.override.md` receives it instead), and a synchronous `SessionStart` callback in `~/.codex/hooks.json` |
| Cursor | `~/.cursor/skills/human-outcome-reporting/` | A user `sessionStart` hook in `~/.cursor/hooks.json` injects the reporting preference and installed skill path |

The installer merges existing settings and hooks under an account-level transaction lock. It never creates `CLAUDE.md`,
changes permissions, replaces safety hooks, or activates a framework globally.
An installation state with protected before-images is saved in
`~/.local/state/datarim-human-reporting/` (directory mode 0700, files mode 0600).
These backups may contain existing private client settings; keep them local.

The mechanisms are documented by [Claude output styles](https://code.claude.com/docs/en/output-styles),
[Claude startup hooks](https://code.claude.com/docs/en/hooks#sessionstart),
[Codex startup hooks and trust](https://learn.chatgpt.com/docs/hooks),
[Codex instruction discovery](https://developers.openai.com/codex/guides/agents-md),
and [Cursor user hooks](https://cursor.com/docs/hooks). Each client must support
its native feature; client version alone is not a behavior test. Skill discovery
is separate from guaranteed instruction compliance.

The Codex and Claude callbacks live in the respective user `hooks/` directory.
They run synchronously with a ten-second timeout, read only the native `cwd`
metadata field and resolve preferences before the first progress message or
other human text. They ignore transcript paths, prompts and unrelated payload
fields. Missing or malformed metadata, an unavailable resolver or invalid
configuration produces a fixed unresolved-preference notice; it does not claim
that English defaults or a configured language were applied.

Codex 0.160.0 supports this startup contract. New or changed non-managed hook
definitions must be reviewed through native `/hooks` before Codex runs them.
The installer does not modify `config.toml`, `hooks.state`, trusted hashes,
feature switches, managed policy or native approvals. Existing inline and JSON
hooks retain their own native configuration and trust. If hooks are disabled,
unsupported or awaiting review, installing a definition does not activate it.
Review only the new reporting callback through the client's supported flow;
never bypass hook trust. A callback timeout or failure also leaves startup
preferences unmeasured. Verify the first actual reply independently.

Restart existing sessions after installing or updating. In Cursor, create a new
conversation: resuming an old chat does not rerun its session-start hook. Claude project settings
can override the user output style. Codex project instructions can override user
preferences. Cursor local user hooks and skills do not automatically propagate
to cloud workers or another SSH account. Use an authorized installation in each
remote account, or project/team configuration on a worker. User preferences are
instructions, not a deterministic semantic gate.

## Choose languages

Replies and generated artifact prose default to English. The standalone helper
reads the same user preferences as project Datarim without enabling its workflow:

```bash
python3 human-outcome-reporting/scripts/language.py configure --scope user --replies fr --artifacts en
python3 human-outcome-reporting/scripts/language.py resolve
```

These paths work from the extracted archive. After installation use the helper
inside your client's skill directory. User settings live at
`$XDG_CONFIG_HOME/datarim/config.yaml`, falling back to
`~/.config/datarim/config.yaml`. Run `resolve --project /path/to/project` to
include shared and private project preferences. Existing native personal choices
and managed/security rules retain authority. Preferences are read on resolution;
new native sessions avoid retaining earlier context. Cursor refreshes its context
when a new conversation starts. Codex and Claude refresh preferences at each
`SessionStart`, including resume; no reinstall is required after a configuration
change. An already running conversation retains its prior startup context until
that event runs again. See [configure languages](configure-languages.md)
and [precedence and catalogs](../reference/language-preferences.md).

A reusable Markdown note or document excerpt authored inside a chat reply is
still an artifact. Its generated prose and examples use artifact language;
the explanation surrounding it uses reply language. Do not add a translated
example that was not requested. Explicit bilingual or translation requests,
verbatim input, code and protocol identifiers keep their existing exceptions.

## Check a real session

`check` verifies installed file hashes and reports behavior as `not_measured`.
Its `startup_context` and Codex trust observations remain `not_measured`; an
installation receipt reports new Codex definitions as `native_review_required`.
To test behavior, start a new session in a disposable directory without Datarim.
Ask the client to explain a task whose files are complete but whose production
check has not run. Verify that it explains the usable result and explicitly
states the production uncertainty. Request a clearer explanation and verify that
it reads or explains existing evidence without resuming edits or deployment.
Keep the prompt, native client version, answer, and any tool calls as evidence.
Also select different reply and artifact preferences, start a cold session
without requesting a language in the prompt, and check the first progress text
as well as the final answer and generated document. Change the configuration
without reinstalling and repeat. Check that an explicit document-language
request and the native permission boundary still hold.
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
removes only its Codex section and owned startup handlers, and preserves later unrelated
settings and rules. If someone changed an owned file or selected another Claude
style, uninstall refuses to overwrite it. The installer does not remove empty
client directories. If foreign startup groups were appended after the owned
group, uninstall leaves an empty group at its index so their Codex trust
identities stay stable. Keep operation receipts separately from the package so they
remain available after an update or uninstall.

Inside Datarim, [Human Outcome Reporting](../../skills/human-outcome-reporting/SKILL.md)
is loaded by the existing command and agent paths. A host installation and a
project runtime follow the same communication policy; neither grants new
execution permissions or changes acceptance criteria.
