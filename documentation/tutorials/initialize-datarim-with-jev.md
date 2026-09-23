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

Run an explicit network check after saving the key:

```bash
jev doctor --api
```

Offline doctor does not contact Jev. It reports missing clients, key readiness,
and the installed source revision; native instruction loading remains a
separate live check. API doctor distinguishes missing credentials and provider
failure from success.

The following are equivalent entrypoints for their selected clients:

```bash
jevcodex "Review the current task and propose its next implementation step"
jevclaude "Review the current task and propose its next implementation step"
jevcursor "Review the current task and propose its next implementation step"
jev --agent=codex "Review the current task and propose its next implementation step"
```

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
