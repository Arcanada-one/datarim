# Jev control plane for Datarim

The supported interface is project-local and covers Codex, Claude Code, and
Cursor. The former user-scope installation instructions have been retired.

Start with [initialize Datarim with Jev](../tutorials/initialize-datarim-with-jev.md).
Use [configuration and operation](configure-and-use-jev.md) for private key
files, endpoint settings, modes, per-account model mapping, and troubleshooting.
The [CLI reference](../reference/jev-cli.md) documents `jevcodex`, `jevclaude`,
`jevcursor`, and `jev --agent={codex,claude,cursor}`.

## Decisions and execution

Jev receives a bounded task description and a shortlist derived from the local
component catalog. Routing separates complexity, system-2 demand, risk,
component selection, and suggested validation. A recommendation is advisory;
it does not grant tool permissions or prove that the selected agent completed
the task correctly.

Direct mode classifies the initial task. Supervised `--live` mode re-evaluates
phase changes and periodically checks ongoing work with hysteresis. Claude
control requests and Codex/Cursor resume operations have different contracts;
see the [runtime comparison](../../plugins/dr-jev-control/README.md#routing-and-continuity).

## Evidence and failure behavior

`jev stats` reads the current project's redacted ledger. Assess recommendations,
applied switches, blocked switches, failed turns, completed turns, and observed
outcomes separately. A confident rejection is not an ignored recommendation.
No switching can be a valid outcome when the recommended tier has not changed.

Missing keys, network failures, and unavailable Jev advice leave the native
client usable. A project off switch suppresses API advice while the installed
Claude deterministic pre-tool floor remains active. This does not imply that
Claude hooks exist in Codex or Cursor. Native client permissions still apply.

API access, native AGENTS loading, session continuity, and quality/cost outcomes
are separate checks. Prior report numbers belong to their measured revisions
and hosts; they are not acceptance evidence for a newly installed project.

## Codex: installing a hook is not enabling it

Writing the hooks into `~/.codex/hooks.json` does not make Codex run them. It
gates them behind two prompts, both in its TUI, and declining either is silent:

1. **Trust the working directory.** Codex's own prompt says it plainly —
   project-local config, hooks and exec policies do not load until you accept.
2. **`Hooks need review — N hooks are new or changed`.** The third option is
   `Continue without trusting (hooks won't run)`.

Do not judge this from the client's hook screen. Its `Active` column counts
hooks that are *installed*, so it reads the same either way: measured, it showed
`UserPromptSubmit 2/2 Active` while the ledger had recorded zero such events
over 45 minutes and the routing model had therefore classified nothing Codex was
asked to do.

Two authorities give a real answer:

```sh
jev doctor --agent=codex     # codex_hook_trust: trusted | untrusted | not_measured
```

and the ledger itself — events grouped by `hook_context.client` and
`native_event`. A whole class of events missing while another class arrives is a
trust gate, not a broken hook.

### What Codex actually compares

Codex runs a user hook only while two things hold (codex-rs
`hooks/src/engine/discovery.rs`):

- its state block in `~/.codex/config.toml` is not `enabled = false`, and
- the block's `trusted_hash` equals the hash of the hook **as it stands now**.

That hash is sha256 over the event, the matcher and the normalised handler —
**including the command string**. Change the command and a trusted hook becomes
*modified*: Codex skips it without a prompt in `codex exec` and asks again in
the TUI. `enabled = true` appears on some blocks and not others; it is not what
decides trust.

This is why the host installer registers a **stable command**:

```text
<python> ~/.local/share/jev/bin/jev-hook codex UserPromptSubmit
```

`jev-hook` reads the active release from `~/.config/jev/installation.json` and
hands over to it, so the command — and the hash — stay the same across upgrades.
Earlier installs wrote `…/releases/<sha>/scripts/jev_hook.py`; measured on
codex-cli 0.156.1, one upgrade in that form stopped Jev's Codex hooks on three
hosts while every unchanged hook kept running. The first install that switches
to the stable command changes it one last time, so accept **Trust all** once
more after it; later upgrades do not ask.

`jev doctor` recomputes the hash Codex compares and reports, per hook, whether
it is `trusted`, `modified` (trusted once, command changed since), `untrusted`
(never trusted) or `disabled`. The overall state is `trusted` only when every Jev
hook is. Trust is per machine, and `not_measured` — never `trusted` — is
reported when there is no configuration to read, because an absent file answers
nothing.

An earlier revision of this page said an upgrade does not re-arm the gate and
that the hash is not taken over the command. Both were wrong: the hash
comparison above is read from the Codex source and was checked against hashes
Codex wrote itself.

## Integrity

From the source checkout, verify the plugin manifest with:

```sh
shasum -a 256 -c JEV-MANIFEST.sha256
```

The manifest covers shipped source files and project integration entrypoints.
Regenerate it only after reviewing the corresponding source changes, then
include its diff in the same pull request. The installation manifest separately
records the project root, source revision, and installed source-content digest.
