# Use Jev on its own, without Datarim

Jev is a routing layer for Claude Code, Codex CLI and Cursor. It does not need
Datarim, and installing it does not install Datarim. This page covers the case
where you want classification and the deterministic safety floor on a machine
whose projects have nothing to do with the framework.

Every command here was executed on a real host before being written down.

## Which of the four combinations you are in

| | Datarim | Jev | Install with |
|---|---|---|---|
| Framework + routing | yes | yes | `./install.sh --project P --init --with-jev` |
| Framework only | yes | no | `./install.sh --project P --init` |
| **Routing only** | no | yes | `jev_host_install.py --client …` ← this page |
| Neither | no | no | nothing to install |

Host Jev is per-machine and per-user. It is installed once and applies to every
project that user opens, which is why it suits a machine where all work happens
in one directory.

## Install

From a reviewed checkout of this repository, on the machine and under the
account that will run the agents:

```sh
git clone https://github.com/Arcanada-one/datarim.git ~/src/datarim-jev
cd ~/src/datarim-jev
python3 scripts/jev_host_install.py --client claude --dry-run
python3 scripts/jev_host_install.py --client claude
python3 scripts/jev_host_install.py --client codex
```

Run `--dry-run` first: it prints every file the install would touch, and
nothing else is written. The real run reports where it put the runtime and
where it left a backup.

Only these paths are created or modified:

```
~/.config/jev/config.json
~/.config/jev/installation.json
~/.claude/settings.json          (merged, see below)
~/.local/bin/jev jevclaude jevcodex jevcursor
~/.local/share/jev/releases/<sha>/
```

**Existing hooks are preserved.** Measured on a host whose
`~/.claude/settings.json` already carried twelve unrelated hooks: after
installing, all twelve were still present byte-for-byte, three Jev hooks had
been added, and every other key in the file was unchanged. An upgrade replaces
the Jev entries only, leaving foreign ones alone.

Add `--home` to install into a different account's home, and
`--client cursor` if you use Cursor.

## The API key

The installer creates an **empty** key file, mode `0600`, in a private
directory. It never overwrites an existing one.

```
~/.config/jev/credentials/api-key
```

Open it in an editor and paste one key on one line:

```sh
# macOS
open -t ~/.config/jev/credentials/api-key
# Linux
nano ~/.config/jev/credentials/api-key
```

Use a **different key on each machine**. Do not echo it into the file from a
shell (it lands in history), do not put it in a commit, a settings file, or a
prompt.

Check it:

```sh
jev doctor          # key_ready: true
jev doctor --api    # contacts the service
```

`--api` returns the model and the round trip, e.g. `"ok": true, "model":
"jev-1.13.0", "ms": 313.8`. Without `--api` no network call is made at all:
offline `doctor` reports `api: not_measured`, which is a third verdict and must
not be read as either pass or fail.

## Run an agent through Jev

```sh
jevclaude "Review this change"
jevcodex  "Investigate the failing test"
jevcursor "Explain this module"
jev --agent=codex "Investigate the failing test"     # same thing, long form
```

Resume an existing session:

```sh
jevclaude --resume <session-id> "continue"
jevcodex  --resume <session-id> --effort high "continue"
```

Codex `resume` does **not** inherit the model or the reasoning effort — state
`--effort` again or it silently falls back to the default.

Add `--dry-run` to any of these to see what would run without running it.

## What you get without Datarim

The routing advice injected before each prompt contains the suggested model
tier, agent fan-out, context budget, validation policy, and scores for
reasoning demand, production risk and parallelisability.

It does **not** contain skill, agent, command or template suggestions: those
are chosen from a project's Datarim catalogue, and without a catalogue there
are no candidates. This is by design, not a failure. Measured with one prompt
on one host: with a catalogue present the advice named four skills with scores,
an agent and a command; in a directory without one, the same prompt returned
the tier advice alone and no catalogue line.

The deterministic safety floor is independent of all of this. It runs locally,
needs no key, and is not disabled by `jev off`. Measured on two hosts, 15
commands: it blocks raw writes and filesystem formats to a block device,
recursive deletion of protected roots — including the spellings `rm -fr /`,
`rm -r -f /`, `rm -rf ~`, `rm -rf $HOME` — and `git push --force`, while
allowing ordinary `dd`, `mkfs` to an image file, `rm -rf ./build` and
`git push --force-with-lease`. It is deliberately narrow: graded risk is the
advisory layer's job, so a fork bomb, for instance, is not blocked.

### If advice arrives without the catalogue line

The hook gives the routing call a short budget — 4 s for the API, and the
wrapper kills the child at 6 s — because a prompt must not hang waiting for
advice. When the round trip exceeds it, the hook returns whatever it has, or
nothing, and your session continues unadvised. Measured round trip on a healthy
link: 0.6 s.

So intermittent "no skills suggested" on a slow or distant network is a
timeout, not a misconfiguration. Raise it in the host config
(`~/.config/jev/config.json`) if that is your situation:

```json
{ "api": { "hook_timeout_seconds": 10 } }
```

### What the advice costs

Measured on three prompts of different sizes, three runs each: **0.5 s** and
roughly **3400 input / 790 output tokens per prompt**, near-flat across prompt
size because the project catalogue dominates the input, not your text.

Without a Datarim catalogue there is nothing to probe, so the cost is far
lower — this section describes the catalogue case.

If that is too much for your workload, the dominant term is how many catalogue
candidates get probed:

```json
{ "routing": { "component_selection": { "candidate_probe_limit": 4 } } }
```

Measured, not assumed: dropping the limit from 8 to 2 moved one prompt from
3417/789 to 2836/640 tokens — about 17%, not the proportional cut you might
expect. Most of the input is the catalogue itself and the task description,
which are sent regardless; only the per-candidate probes scale. Lower it if you
want, but do not expect the cost to fall with the limit.

Whether the advice pays for itself — fewer wrong turns and fewer irrelevant
skills loaded, against ~3400 tokens a prompt — depends on your work, and this
project does not claim a figure it has not measured.

## Turn it off

```sh
jev off       # stop consulting the API for this project
jev on
jev --no-route "…"    # one invocation only
```

`jev off` suppresses the advisory API. The local safety floor stays active —
that is deliberate, and it is why there is no global off switch.

To remove Jev from a machine entirely, delete the paths listed above; the
install backup under `~/.local/state/jev/install-backup-*` holds the previous
`settings.json`.

## Verify

```sh
jev doctor
```

- `findings: []` — nothing wrong that the tool can see.
- `key_ready` — whether a key is present, not whether it is valid; use `--api`.
- `datarim_enabled: false` — expected here; it means no project catalogue.
- `codex_hook_trust` — see below.
- `api` / `native_agents_live`: `not_measured` offline.

## Codex needs two approvals in its own UI

Writing the hooks does not make Codex run them. It asks twice, in the TUI, and
declining either is silent:

1. trust the working directory;
2. `Hooks need review — N hooks are new or changed` → **Trust all and
   continue**. The third option is `Continue without trusting (hooks won't
   run)`.

Do not judge this from the client's hook screen: its `Active` column counts
hooks that are *installed*. Measured, it read `2/2 Active` while the ledger had
recorded zero such events.

`jev doctor` answers instead, with `codex_hook_trust`. It recomputes the hash
Codex compares for each Jev hook:

- `trusted` — every Jev hook will run;
- `untrusted` with `pending` — at least one will not, and the entry says why:
  - `modified` — trusted once, but the command has changed since;
  - `untrusted` — never trusted;
  - `disabled` — switched off in the client's `/hooks` screen;
- `not_measured` — no configuration to read.

### Upgrades keep your approval

Codex's trust is a hash **over the hook's command**, so any change to the
command drops it. The installer therefore registers one stable command,
`~/.local/share/jev/bin/jev-hook`, which finds the active release itself. Upgrade
as often as you like: the command, and your approval, stay the same.

One exception: if the machine was installed before this change, its hooks named
`…/releases/<sha>/…` directly. The first upgrade rewrites them to the stable
command, so open `codex` once more and choose **Trust all and continue**. After
that, upgrades do not ask again.

### Automation that cannot answer a prompt

Codex ships a flag for this, and on 0.155.1 it works:

```sh
codex exec --dangerously-bypass-hook-trust "…"
```

Measured with a fresh `CODEX_HOME` holding the hooks but no trust records:
without the flag no hook ran at all and the run completed silently; with it,
`SessionStart` and `UserPromptSubmit` ran, the client printed a warning that
trust was bypassed, and the events arrived in the Jev ledger.

Use it only where the hook sources are already vetted — it is what the flag's
own help says, and it is the difference between "I reviewed these hooks" and
"something wrote hooks into my home". For an interactive workstation, accept
the prompt once instead.

Two limitations worth knowing before relying on it: the flag was reported
ineffective in TUI mode on 0.131–0.133 (fixed by 0.155.1 in `exec` mode as
measured here), and it applies to a single invocation, not to the machine.

## Cursor

Prepared and installed by the same command, but **untested**: the subscription
used for verification has lapsed. It is not claimed to work.
