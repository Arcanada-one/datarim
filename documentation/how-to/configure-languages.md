# Configure reply and artifact languages

Choose the language of conversation independently from the language of generated
plans, requirements and reports. Both default to English. Language preferences
do not enable Datarim, change native project rules or grant execution permissions.

## Set a personal preference

In an installed Datarim project, run:

```bash
python3 .datarim-runtime/skills/human-outcome-reporting/scripts/language.py configure --scope user --replies fr --artifacts en
python3 .datarim-runtime/skills/human-outcome-reporting/scripts/language.py resolve --project "$PWD"
```

The first command updates `$XDG_CONFIG_HOME/datarim/config.yaml`, or
`~/.config/datarim/config.yaml` when XDG_CONFIG_HOME is unset. It preserves
unrelated settings. The second prints the resolved languages and their sources.
Use your preferred safe language tag, for example `de`, `es`, `pt-BR` or `ar`.
No country, hostname or operating-system locale chooses it for you.

For a standalone installation, replace the script path with the installed client
skill path, for example
`~/.agents/skills/human-outcome-reporting/scripts/language.py` for Codex. From an
extracted standalone archive use `human-outcome-reporting/scripts/language.py`.
The configuration is shared across these installations in the same account.

## Set project document defaults

```bash
python3 .datarim-runtime/skills/human-outcome-reporting/scripts/language.py configure --scope project --project "$PWD" --artifacts en
```

Shared defaults live in `datarim/config.yaml`. Set a personal project override
with `configure --scope local --project "$PWD" --replies de --artifacts en`;
it writes `datarim/config.local.yaml`:

```yaml
language:
  replies: de
  artifacts: en
```

Keep `config.local.yaml` private. Project installation hides `datarim/` through
`.git/info/exclude`; `config.yaml` is therefore not automatically team-shared.
If your team chooses to track it, review and explicitly include only that file,
while keeping local overrides and task data ignored. See the
[configuration template](../../templates/datarim-config.yaml).

Reply precedence after explicit overrides is private project, personal user,
shared project, then English. Artifact precedence is private project, shared
project or the legacy `Artifact language: <tag>` project directive, personal
user, then English. Different reply and artifact values are intentional.

If shared YAML and the legacy directive specify different artifact languages,
resolution fails. Reconcile them or remove the legacy directive after migrating
its value; never silently pick one. Malformed preferences must also be corrected
before treating language resolution as successful.

## Override one task

Ask the agent explicitly, for example: "Reply in French and write this plan in
English." Agents can resolve that request using `--replies` and `--artifacts`.
Delegated processes receive `DATARIM_REPLY_LANG` and `DATARIM_ARTIFACT_LANG` for
that launch. Do not put those variables in shell startup files.

```bash
python3 .datarim-runtime/skills/human-outcome-reporting/scripts/language.py resolve --project "$PWD" --replies fr --artifacts en --format context
```

Preferences are read again when the resolver runs; they need no reinstall.
Existing conversation context can retain old instructions. Start a new session
after changing native adapters; Cursor's session-start context is refreshed in a
new conversation. Explicit native personal settings and managed/security rules
retain their authority.

## Check the result

Inspect both values and their sources, then ask for a short reply and a short
document in a fresh session. Check the reply, generated document prose and any
fixed renderer labels separately. Preserve quoted briefs, existing content,
code, filenames and machine enum values.

The agent can generate prose in the requested language, but fixed report labels
require an available renderer catalog. An unavailable catalog uses a
disclosed English fallback. A passing configuration check does not prove model
compliance in Claude Code, Codex or Cursor. See the
[reference](../reference/language-preferences.md) and
[hands-on tutorial](../tutorials/language-preferences.md).
