# Use host Jev with project-local Datarim

Jev can classify work for Claude Code, Codex, and Cursor across a host without
enabling Datarim globally. Datarim is an optional catalog provider, enabled only
for explicitly approved project installations. Keep all project instructions
in `AGENTS.md`; installing Jev does not install global framework instructions.

## Install a verified runtime

Run from a clean, reviewed checkout of the Datarim repository. The installer
copies the Jev engine into a revision-specific runtime; it does not point hooks
at your editable checkout. Replace the example project path with your project.

```sh
python3 scripts/jev_host_install.py \
  --client claude --client codex --client cursor \
  --datarim-project /absolute/path/to/project --dry-run
```

Review the proposed paths, then repeat without `--dry-run`. Existing unrelated
hooks are retained. To retire a previous Jev source directory, explicitly add
`--replace-legacy-root /absolute/path/to/old-source`; only recognized Jev hook
commands under that directory are replaced. No shell startup file is changed.
The four launchers are written to `~/.local/bin`, which must be on your PATH.

The installer records a private backup and reports its path. Native Codex hook
definitions require review through `/hooks` in a fresh Codex session; the
installer does not grant that trust. Afterwards, `jev trust` (and `jevcodex`,
unless `JEV_NO_AUTO_TRUST=1`) re-grants it to Jev's own hooks only, when another
tool has moved them. A successful file installation is not evidence that a
client has loaded, trusted, or executed its hooks.

`--datarim-project` replaces the host's whole `datarim_projects` list; pass
every approved project each time. The complete install sequence is in
[INSTALL.md](../../INSTALL.md#only-if-the-user-chose-host-jev-install-host-jev-first), the host Jev step.

## Add the host key

The installer creates this empty private file:

```text
~/.config/jev/credentials/api-key
```

Open it in your local editor and paste only the newly issued Jev API key. Keep
mode `0600`. Issue a different key on each computer. Do not paste the key into a
terminal command, chat, tracked configuration, or agent prompt. Host Jev uses
this file and `~/.config/jev/config.json`; a project's configuration cannot
redirect the host credential to another API endpoint.

Check local prerequisites, then explicitly test the provider connection:

```sh
jev doctor
jev doctor --api
```

The first command does not contact Jev. Empty keys and unavailable APIs leave
classification unavailable; the local deterministic command guard remains
independent. `jev off` disables host API calls, including retries; `jev on`
reenables them. Neither command removes that guard.

## Enable Datarim in a project

After registering host Jev, run the project installer in the approved project:

```sh
./install.sh --project /absolute/path/to/project   # prints the questions to ask and the flags for each answer
```

Ask the user its questions; for the Jev answer "host" it lists
`--with-jev --host-jev`. `--host-jev` assigns hook ownership to the existing host installation and avoids
registering a second set of project hooks. The host config's `datarim_projects`
allowlist must also contain the physical project root. Nested Git repositories
require explicit `--context relative/path` entries on the project installation.
For a server that should have project-only Jev, omit `--host-jev` and follow the
[project initialization tutorial](../tutorials/initialize-datarim-with-jev.md).

## Launch clients

```sh
jevcodex "Review this change"
jevclaude "Implement the documented plan"
jevcursor "Investigate this failure"
jev --agent=codex "Review this change"
jev --agent=claude --live --max-turns 4 "Implement the documented plan"
```

An ordinary native client launch receives hook advice after its hook definition
is active. A wrapper can classify the initial task and choose a mapped model or
reasoning effort before launch. `--live` uses the supervisor for supported
session continuation. Hook advice alone does not switch the running model.
See the [CLI reference](../reference/jev-cli.md) for flags and mappings.

## Verify behavior and measure value

Check both an approved Datarim project and an unrelated directory. The latter
must receive no Datarim catalog or workflow and must create no `datarim/` or
`.datarim-runtime/` directory. Host telemetry belongs under `~/.local/state/jev`,
partitioned by physical working directory and session. Prompt text is not stored
by default. Classification is an observation; emitting advice is not proof that
the agent followed it.

Cursor's `beforeSubmitPrompt` cannot inject advice. Its classification can be
recorded, while supported tool hooks can emit advice in their native schema.
Claude, Codex, and Cursor have different hook contracts and trust behavior;
verify fresh sessions on the installed versions. GUI and CLI parity, model
switching, quality, latency, and cost savings require separate live receipts.
Do not infer savings from a lower recommended tier: classifier charges and
prompt-cache recreation can outweigh it.

Sources: [Claude hooks](https://code.claude.com/docs/en/hooks),
[Codex hooks](https://learn.chatgpt.com/docs/hooks),
[Codex App Server](https://learn.chatgpt.com/docs/app-server),
[Cursor hooks](https://cursor.com/docs/hooks).


## Independent catalogs without a framework project

The standalone host runtime can use explicitly authorized catalogs without
setting `DATARIM_ROOT`, installing Datarim into a project, or recreating global
framework symlinks. Nothing is discovered from the event working directory or
an ambient catalog environment variable. Empty `catalog_roots` remains the default.

Prepare a separate directory containing `skills/<name>/SKILL.md`, `agents/*.md`,
`commands/*.md`, and optionally `templates/*.md`. Each file should have a one-line
`description:` metadata field. Only that description (up to 280 characters),
component identity and digest are used for selection; component bodies are not
sent as candidate descriptions. Authorizing a directory permits this metadata to
be sent to the configured decision provider, so do not include private content.

Run the normal verified host installer with the additional repeatable argument
`--catalog-root team=/absolute/path/to/catalog`. The argument replaces the entire
independent provider list; it does not append silently. Use `--dry-run` to review
the proposed installer changes first. The installer writes the list only into the
protected host config. It leaves `datarim_projects` unchanged. To revoke all
independent catalogs, rerun it with `--clear-catalog-roots`. The same installer
release/trust and rollback procedure still applies; do not install an unmerged
source revision on a real host.

Providers have unique IDs; candidates are namespaced as `team--review`. Paths
must be canonical absolute directories, without symlinks or external write bits.
Traversal never follows directory symlinks and file symlinks are refused. Each
provider/kind is limited to 512 traversal entries, each kind to 128 candidates
across providers, and each file to 64 KiB; at most eight providers are allowed.
Invalid, ambiguous or over-limit catalogs refuse routing through the existing
advisory fail-open handler; the deterministic tool safety floor stays independent.
An explicitly configured independent catalog takes precedence over legacy project
catalogs, so the two authority sources are not silently mixed.

The existing skill probability gates and single-choice confidence gate select
components. The native prompt hook includes selected paths and SHA256 values as
quoted JSON metadata. It does not execute commands, spawn agents, import skills,
or turn recommendations into authorization. Verify the source digest and project
policy before loading a component. Cached wrapper advice is invalidated if the
catalog configuration or contents changed, including revocation. Actual agent
loading remains a separate observation, not an implication of hook delivery.

Offline verification: `python3 -m unittest discover -s tests -p 'test_jev_independent_catalog.py'`.
