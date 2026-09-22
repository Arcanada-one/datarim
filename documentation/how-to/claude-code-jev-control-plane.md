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

## Integrity

From the source checkout, verify the plugin manifest with:

```sh
shasum -a 256 -c JEV-MANIFEST.sha256
```

The manifest covers shipped source files and project integration entrypoints.
Regenerate it only after reviewing the corresponding source changes, then
include its diff in the same pull request. The installation manifest separately
records the project root, source revision, and installed source-content digest.
