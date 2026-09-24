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
[INSTALL.md](../../INSTALL.md), option C.

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

After registering host Jev, initialize the approved project:

```sh
python3 scripts/project_install.py --project /absolute/path/to/project \
  --init --with-jev --host-jev
```

`--host-jev` assigns hook ownership to the existing host installation and avoids
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
