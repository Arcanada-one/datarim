# Language preferences reference

Available from Datarim 4.3.0 and the matching standalone Human Outcome Reporting
package. Canonical resolver:
[`language.py`](../../skills/human-outcome-reporting/scripts/language.py).

## Configuration

```yaml
language:
  replies: en
  artifacts: en
```

Both keys accept safe language tags, including regional subtags, without a
Russian/English whitelist. They choose generated presentation, not the language
of instructions shipped in the Datarim repository, which remain English.

| Source | Location | Scope |
| --- | --- | --- |
| Private project | `<project>/datarim/config.local.yaml` | Personal overrides for that project |
| Shared project | `<project>/datarim/config.yaml` | Project defaults; tracking is an explicit team choice |
| User | `$XDG_CONFIG_HOME/datarim/config.yaml`, otherwise `~/.config/datarim/config.yaml` | Personal defaults for the account |
| Legacy project | `Artifact language: <tag>` in project `AGENTS.md` | Artifact-only compatibility directive |

With `--project PATH`, discovery starts at that directory; otherwise it starts
at the current working directory. It uses the nearest ancestor with `.git`,
`.datarim-runtime/` or `datarim/config.yaml`, and otherwise uses the starting
directory. Configuration does not activate that directory as a Datarim project.

No preference file is needed for the English defaults. Standalone reporting reads
the same preferences without creating a Datarim runtime or task directory.

## Resolution order

Highest priority first, resolved independently for each key:

| Replies | Artifacts |
| --- | --- |
| Explicit CLI `--replies` | Explicit CLI `--artifacts` |
| Delegated `DATARIM_REPLY_LANG` | Delegated `DATARIM_ARTIFACT_LANG` |
| Private project YAML | Private project YAML |
| Personal user YAML | Shared project YAML / legacy project directive |
| Shared project YAML | Personal user YAML |
| `en` | `en` |

The YAML artifact value and legacy directive must agree when both exist;
conflict is an error. A project document policy therefore takes precedence over
a personal document default. Native managed/security rules retain authority;
preferences do not override permissions or an explicitly requested document
language. The resolver does not infer a language from the latest message,
country, hostname or operating-system locale.

## CLI and API

```text
language.py resolve [--project PATH] [--user-config PATH] [--project-config PATH]
                    [--replies TAG] [--artifacts TAG] [--format json|context]
language.py configure --scope user|project|local [--project PATH]
                      [--user-config PATH] [--project-config PATH]
                      [--replies TAG] [--artifacts TAG]
```

JSON output uses schema `datarim-language-preferences/1` and includes `replies`,
`artifacts`, `sources`, `direction` and `warnings`. `--format context` emits
concise English instructions with the resolved tags for native agent context.
Python API:

```python
resolve_preferences(project=None, user_config=None, project_config=None,
                    replies=None, artifacts=None, environ=None)
```

Configuration accepts JSON or a YAML mapping with a scalar-only `language`
block; it does not execute YAML tags or interpolate values. Malformed input,
duplicate keys and conflicting project directives return exit code 2.
`configure --scope local --project PATH` writes the private project file.
Configuration writes preserve unrelated YAML settings and validate before an
atomic write. Symlink destinations are refused. Keep files with private project
or account preferences outside public source.

## Presentation and preservation

`replies` controls human-facing conversational output. `artifacts` controls
free-generated document prose, including generated explanatory sections. Exact
briefs and quotations retain their original bytes;
existing user content is not automatically translated. Code, paths, identifiers,
JSON schema keys and enum values remain stable. Translation is not evidence of
completion, acceptance or reader understanding.

The deterministic report renderer localizes fixed labels through language
catalogs. Accepted preference tags are broader than its catalog coverage. Missing
catalog coverage uses an explicitly disclosed English fallback; user-authored
report values are not machine-translated. Additional catalogs must follow the
renderer catalog schema and be validated before inclusion; there is no arbitrary
custom-catalog CLI option. Customer-delivery receipt locale matrices follow the
task-declared site locales;
a reply preference is not a declaration that those site locales were tested.

## Report renderer

```text
hr.py render --contract PATH --report PATH [--evidence-root PATH]
             [--language TAG] [--project ROOT]
```

`render` writes a human-facing report to stdout and defaults to the resolved
**reply** language. To save a document, explicitly pass the resolved **artifact**
language as `--language`; redirecting stdout does not change language selection.
The agent must generate the supplied contract/report prose in its intended
language first. The renderer changes fixed labels only, preserving supplied prose.
Bundled complete catalogs are `en`, `ru`, `fr`, `ar` and `ja`.
A regional tag can use its primary-language catalog. A presentation comment
records requested tag, chosen catalog, preference source and writing direction; unavailable catalogs
also produce a visible English fallback notice. Arabic uses ordinary Unicode
and RTL metadata; the displaying application controls bidirectional layout.
See the [presentation contract](../../skills/human-outcome-reporting/references/presentation.md).

## Native integration limits

Claude Code uses its output style and skill; Codex uses native instruction/skill
loading; Cursor injects resolved context through its session-start hook. Local
Cursor settings do not automatically reach cloud workers or another SSH account.
Preference changes take effect on resolution, but a running conversation may
retain previously loaded context. Installation and config checks establish file
state, not live model behavior. Record runtime, prompt, answer and tool calls for
an actual behavior observation.

See [configuration steps](../how-to/configure-languages.md),
[standalone installation](../how-to/install-human-outcome-reporting.md) and
[reporting contract](../human-reporting/README.md).
