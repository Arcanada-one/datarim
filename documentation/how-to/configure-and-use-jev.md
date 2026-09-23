# Configure and use Jev

Configuration is local to the installed project:

| Path | Purpose |
|---|---|
| `AGENTS.md` | Canonical project instructions |
| `.datarim-runtime/installation.json` | Source revision, content digest, project root, approved nested contexts |
| `.datarim-runtime/jev-config.json` | API endpoint, routing profiles, hook budgets, hysteresis and ledger settings |
| `.datarim-runtime/state/jev/ledger.jsonl` | Redacted decision and execution evidence |
| `.datarim-runtime/state/jev/DISABLED` | Project off switch |
| `config/credentials/jev/api-key` | Host-specific TypeSafe key; mode 0600 |
| `.claude/settings.local.json` | Project-local Jev hook registrations; unrelated settings preserved |

The default API is TypeSafe systemone with model `jev-latest`. Configure its
endpoint, timeout and retries in `jev-config.json`; do not send a real key to an
untrusted replacement endpoint. CLI request budgets and hook budgets are
separate because the host imposes a hard hook deadline. Do not increase hook
timeouts/retries without checking the complete deadline envelope.

Use `--mode economy`, `--mode balanced` (default), or `--mode quality`. A mode
guides recommendations; it does not authorize additional actions. Explicit
`--model` and `--effort` overrides take precedence in direct mode. Live mode
currently rejects those overrides instead of silently ignoring them.

Claude tiers map to its named tiers. Codex defaults to its configured account
model and maps Jev tiers to low/medium/high effort. For per-tier model overrides
set `DATARIM_CODEX_MODEL_HAIKU`, `DATARIM_CODEX_MODEL_SONNET`, and
`DATARIM_CODEX_MODEL_OPUS` in the current project shell, using IDs your account
actually supports.

For Cursor, inspect `cursor-agent --list-models` (or the installed `agent`
binary's model listing). Set `DATARIM_CURSOR_MODEL_HAIKU`,
`DATARIM_CURSOR_MODEL_SONNET`, and `DATARIM_CURSOR_MODEL_OPUS` to supported model
IDs. Without a mapping, direct mode explains that it keeps the client's default;
live mode does not report an unmapped model change as applied. Model availability
is account-dependent. Never copy another machine's unverified list.

Activate only in the current shell:

```bash
cd "$DATARIM_PROJECT"
source .datarim-runtime/activate.sh
jev --agent=claude --dry-run "Inspect project"
jev --agent=claude --print --no-route "Inspect project"
```

Do not add activation to `.zshrc`, `.bashrc`, or global agent settings. Close the
shell to discard activation. Leaving the project makes all entrypoints reject
the invocation even if that shell still has the local bin directory on PATH.

Troubleshooting:

- **No local installation:** enter the intended project or explicitly initialize
  it. There is no search for another project's task store or a home runtime.
- **Missing key/API failure:** fill the protected key file and run `jev doctor
  --api`. Work without routing via `--no-route`; failure is not reported as a
  successful Jev decision.
- **Missing client:** install/authenticate the selected official client, then
  repeat doctor. Installing Datarim does not provision client accounts.
- **Claude ignores AGENTS:** check version, fresh session, ancestor instruction
  files and built-in loader availability. Do not create a CLAUDE adapter or
  change privacy/provider settings silently.
- **Modified managed files:** retain and reconcile local edits before update or
  uninstall. Do not use force overwrite to hide a conflict.
- **No observed switching:** inspect recommendations versus applied decisions in
  `jev stats`. No switching is a possible outcome, not proof of improvement.

Rotate a key by issuing a new host-specific key, replacing the file through a
protected editor, verifying API access, then revoking the old key. Do not reuse
previously exposed provider credentials. API success proves access, not routing
quality, cost savings, or full task correctness.

Official client references: [Claude AGENTS loading](https://code.claude.com/docs/en/memory),
[Codex AGENTS](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[Cursor CLI parameters](https://cursor.com/docs/cli/reference/parameters).
