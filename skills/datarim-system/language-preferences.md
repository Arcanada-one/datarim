# Reply and Artifact Language Resolution

Before every command, directly invoked role, artifact generation or delegation,
resolve preferences for the consuming project (not the framework checkout):

```bash
python3 "${DATARIM_RUNTIME:?}/skills/human-outcome-reporting/scripts/language.py" resolve --project "$PWD" --format context
```

Read the context as instructions. Use `--format json` to inspect `replies`,
`artifacts`, `sources`, `direction` and `warnings`; never source/evaluate output.
Resolution is read-only and does not create a Datarim task or activate it.
Defaults are English replies and English artifact prose (`en`/`en`).

Reply precedence: explicit task override or delegated `DATARIM_REPLY_LANG`,
private project `datarim/config.local.yaml`, personal user config, shared project
`datarim/config.yaml`, then `en`. Artifact precedence: explicit task override or
delegated `DATARIM_ARTIFACT_LANG`, private project config, shared project config
or legacy `Artifact language: <lang>` directive, personal config, then `en`.
Personal config is `$XDG_CONFIG_HOME/datarim/config.yaml`, falling back to
`~/.config/datarim/config.yaml`. All use `language.replies` / `language.artifacts`.
Explicit project YAML conflicting with a legacy directive is a resolution error:
resolve the conflict in its authorized scope before dependent generation.

Use the resolved reply language for conversational explanation, stage results,
chat summaries, CTA labels and questions. Use the artifact language for generated
PRDs, plans, expectations, archives, compliance reports and document headings.
An artifact excerpt requested in chat retains the requested document language.
An explicit task/document request can override one value with `--replies <tag>`
or `--artifacts <tag>`; native security and managed policy remain authoritative.
Do not infer language from the latest message, machine locale, country or host.

Read preferences on each invocation so edits take effect without reinstalling.
When dispatching children, carry both resolved tags in their prompt and export
`DATARIM_REPLY_LANG` / `DATARIM_ARTIFACT_LANG` for child processes. Pass validated
tags as separate quoted arguments; no `eval`, shell-sourced JSON or untrusted
command interpolation. Remote transports must explicitly carry both values.
Child-only overrides stay scoped to that assignment. Exact classifier protocols
and machine-only output remain unchanged even when replies use another language.

Preserve verbatim briefs, append-log quotations, existing authored content,
code, paths, identifiers, enum/status values and historical evidence. Translate
presentation separately from stable machine keys. New expectations keep
`wish`, `success_criterion`, `linked_ac`, `status_history` and `current_status`
identifiers in any document language. Translate the Expectations heading with
its `<!-- datarim:expectations -->` marker intact. Legacy Russian identifiers
remain accepted. Chat summaries use the markers in `human-summary`; translated
headings must not change their meanings or remove acceptance disclosures.

Deterministic reporting catalogs may have fewer languages than model-generated
prose. If the renderer reports an unsupported catalog, disclose its actual
English fallback; never claim it rendered the requested language.
