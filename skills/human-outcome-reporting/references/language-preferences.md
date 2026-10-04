# Independent language preferences

Run the bundled `scripts/language.py resolve --project <active-project> --format context`
before a substantive human report. A standalone installation needs no Datarim
runtime or task folders. Resolve again when preferences change; do not cache a
personal choice in a generated native adapter.

Both `language.replies` and `language.artifacts` default to `en`. User preferences
live at `$XDG_CONFIG_HOME/datarim/config.yaml`, falling back to
`~/.config/datarim/config.yaml`. Shared project defaults use `datarim/config.yaml`;
private overrides use `datarim/config.local.yaml` and must stay out of git.

```yaml
language:
  replies: fr
  artifacts: en
```

Configure through `scripts/language.py configure --scope user --replies fr --artifacts en`.
For project defaults use `--scope project --project <path>`; for private project
overrides use `--scope local --project <path>`. Writing settings preserves unrelated
configuration, validates values, is atomic and refuses symlink destinations.

Explicit `--replies`/`--artifacts` values take precedence over delegated
`DATARIM_REPLY_LANG`/`DATARIM_ARTIFACT_LANG`. Reply preference order is private
project, user, shared project, English. Artifact preference order is private
project, shared project or legacy `Artifact language: <tag>` in project `AGENTS.md`,
user, English. Conflicting project YAML and legacy directives are an error.
Malformed configuration does not silently become a successful English default.

Carry the resolved pair to delegated agents. Native personal language requests
and organizational/security policies retain their authority; preferences do not
grant permissions. Never infer language from a user's country, host name, machine
locale or the most recent message. For an explicit task/document language request,
pass the corresponding override. Conversation language does not translate a document.

Accept language tags beyond English/Russian, including scripts/regions and private
use tags. Agents generate free prose in the resolved target language; do not require
an English/Russian heading whitelist. Preserve quotations, original briefs, code,
paths, protocol fields and enum values. Direction is recorded independently per
language; keep code and tables readable in right-to-left reports.

The deterministic `hr.py` tool localizes presentation labels from bundled catalogs;
it does not translate caller-provided report prose. Human report stdout defaults to
the reply preference. When saving a generated report document, explicitly pass
`--language <resolved-artifact-tag>`. If a presentation catalog is unavailable,
the renderer discloses English label fallback and keeps the requested tag in
presentation metadata. That fallback is not proof that the report is translated.

Structural checks and catalogs do not prove translation quality or user understanding.
Distinguish configured language, actual generated text, semantic review and native
runtime coverage. A documentation/configuration check is not a live agent test.
