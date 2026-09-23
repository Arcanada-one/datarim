# Initialize Datarim with Jev

First follow the project and `AGENTS.md` preparation in
[Initialize Datarim](initialize-datarim.md). Jev is optional: a provider failure
must not prevent plain Datarim work.

Use the same installer for a new project or an existing project-local Datarim:

```bash
python3 "$DATARIM_SOURCE/scripts/project_install.py" --project "$DATARIM_PROJECT" --init --with-jev --dry-run
python3 "$DATARIM_SOURCE/scripts/project_install.py" --project "$DATARIM_PROJECT" --init --with-jev
cd "$DATARIM_PROJECT"
source .datarim-runtime/activate.sh
jev doctor
```

The installation creates `config/credentials/jev/api-key` if absent, with mode
0600 and a private parent directory. Open that file with an editor and paste one
new key on one line. Use a different key on each computer. Never put it into
shell history, README, settings JSON, a prompt, or a Git commit. The credentials
directory is ignored by Git. Existing key files are never overwritten.

**Where the key goes depends on which install you did.** A project install with
its own Jev reads the project file above. A project using an already-installed
*host* Jev (`--host-jev`, and `"host_jev": true` in
`.datarim-runtime/installation.json`) reads the host's file instead:

```
~/.config/jev/credentials/api-key
```

In that case the project's own key file stays empty and unread — which looks
alarming but is correct. `jev doctor` reports `"scope": "host"` when this
applies, and `key_ready` answers for whichever file is actually in use.

Run an explicit network check after saving the key:

```bash
jev doctor --api
```

Success looks like this — the service answered, and it says which model did:

```json
"api": { "ok": true, "model": "jev-1.13.0", "ms": 313.8 }
```

Offline doctor does not contact Jev. It reports missing clients, key readiness,
and the installed source revision; native instruction loading remains a
separate live check. API doctor distinguishes missing credentials and provider
failure from success.

`key_ready` says a key is present, not that it is valid — only `--api` answers
that. And `api: not_measured` in an offline run is a third verdict: it is not a
pass and not a failure, it means the question was not asked.

If the key is missing or wrong, sessions keep working. The hook returns no
advice, records `advice_emitted: false` in the ledger, and the deterministic
safety floor continues to run — it needs no key and no network.

The following are equivalent entrypoints for their selected clients:

```bash
jevcodex "Review the current task and propose its next implementation step"
jevclaude "Review the current task and propose its next implementation step"
jevcursor "Review the current task and propose its next implementation step"
jev --agent=codex "Review the current task and propose its next implementation step"
```

**If you use Codex, it will not run the hooks until you approve them twice.**
The first Codex session asks you to trust the working directory, then shows
`Hooks need review — N hooks are new or changed`; choose **Trust all and
continue**. Declining is silent, and the client's own hook screen cannot show
you the difference — its `Active` column counts hooks that are *installed*.
Confirm with `jev doctor --agent=codex`, which reports `codex_hook_trust` as
`trusted`, `untrusted` or `not_measured`. The
[control-plane guide](../how-to/claude-code-jev-control-plane.md) has the
detail, including the flag for automation that cannot answer a prompt.

Use `--agent=claude` or `--agent=cursor` to select either other client. The alias
and dispatcher share one implementation. Select supported account models before
expecting model changes; [model mapping](../how-to/configure-and-use-jev.md)
explains Codex effort and Cursor model IDs.

For a bounded, supervised task:

```bash
jev --agent=codex --live --max-turns 3 --max-seconds 180 "Inspect only: describe the current project structure"
jev stats
```

Live mode re-evaluates on phase boundaries. Claude uses its control channel;
Codex and Cursor continue the reported session between turns. A missing session
ID stops continuation rather than restarting the task. Supervision does not
grant extra permissions or bypass the client's approval policy.

Disable and restore this project's Jev integration with `jev off` and `jev on`.
`--no-route` disables Jev for one invocation. The local deterministic hook floor
continues when the advisory API is disabled. No global off flag is used.
