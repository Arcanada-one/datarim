# controller-continuation — worker entry for external controllers

An **opt-in** plugin. It is not a core command, is not enabled by default, and is
useful only to a project that runs its own *controller*: a job runner, CI
orchestrator or container launcher that pauses a Datarim pipeline stage on an
ordinary question, collects the answer, and resumes the stage later in a fresh
worker. Without such a controller the entry reports itself unavailable.

| Path | Role |
|------|------|
| `commands/dr-continue-checkpoint.md` | The worker entry prompt (`/dr-continue-checkpoint`). |
| `dev-tools/continuation-bootstrap.mjs` | Reader: validates the controller resources and prints the escaped model view, the provenance view or the workspace comparison. |
| `dev-tools/continuation-provenance.mjs` | Provenance consistency checks and the current-workspace comparison (MATCH / CHANGED / refuse). |
| `dev-tools/continuation-provenance-fs.mjs` | Descriptor-anchored, no-follow, bounded filesystem reads (Linux). |
| `tests/*.test.mjs` | `node --test` suites, run in CI on Linux and macOS. |

## How a controller uses it

1. Mount the pinned framework read-only at `RUNTIME/framework` and place three
   controller-authored resources in `RUNTIME`: `continuation.json` (bootstrap),
   `continuation-control.json` (control v2 or v3) and
   `continuation-provenance.json`. Each must be canonical JSON, mode `0400`,
   and have a single link. `RUNTIME` itself must be canonical, not group- or
   world-writable, and **not writable by the worker** (a read-only mount, or a
   directory whose write bit the worker's uid lacks).
2. Start the worker agent with a static startup descriptor that names the entry
   and the exact reader command line:

   ```sh
   node RUNTIME/framework/plugins/controller-continuation/dev-tools/continuation-bootstrap.mjs \
     --model-view [--runtime-root=<abs>] [--workspace-root=<abs>]
   ```

   The modes are `--model-view`, `--provenance-view` and `--workspace-status`.
   Defaults: `--runtime-root=/worker/runtime`, `--workspace-root=/workspace`.
   Each flag may appear at most once and must be an absolute, normalised path.
   **No environment variable is read**. An inherited variable could point the
   reader somewhere the controller never chose, so explicit arguments in the
   controller's own descriptor are the only override.
3. Enforce production HOLD and any action approvals outside the worker. The
   entry never grants them.

Serve the entry from the read-only framework mount. Do not run
`/dr-plugin enable` for it inside an untrusted workspace. A project install
copies files into the workspace, and a workspace copy of the command text can
be edited by the very source the reader is meant to distrust.

## Platform contract

| Platform | Behaviour |
|----------|-----------|
| Linux | Full descriptor-anchored path: every component opened relative to its parent through `/proc/self/fd` with `O_NOFOLLOW`, identities re-checked before and after reads. |
| Any other (macOS, Windows, BSD) | **Refused.** CLI exits `3`, prints `continuation_unsupported_platform` on stderr and nothing on stdout. Library calls throw an error with that exact message before any filesystem access. |

There is no portable fallback. Node has no `openat`, and macOS `/dev/fd/<n>/name`
does not resolve through a directory descriptor, so a walk there could be raced.
A "best-effort" MATCH would read as a pass. Any other failure exits `1` with
`continuation_unavailable`.

## Schema notes

- `checkpoint.trackerRef` is `null` or an opaque reference to the external work
  item in any tracker, 1–256 characters from `[A-Za-z0-9_.:/#@+-]`, starting
  with an alphanumeric, e.g. `jira:ABC-123` or `github:org/repo#42`. The reader
  never interprets it.
- `checkpoint.taskId` follows the Datarim task-ID form `PREFIX-NNNN`.
- Indexed artifact paths live under the workspace's `datarim/` directory.
- A checkpoint admits a continuation for at most 15 minutes after `createdAt`.
- Control v3 `stageRestart` admits only a superseding-source QA-to-DO restart
  (route `do → qa → compliance`) and re-verifies its attestation and acceptance
  bytes from the workspace against the controller index.

Not yet provided: versioned JSON Schemas, digest test vectors, and a reference
controller. Until they exist, the tests under `tests/` (`fixtures.mjs` builds a
complete synthetic resource set) are the executable specification.

## Tests

```sh
node --test plugins/controller-continuation/tests/*.test.mjs
```

On Linux every test runs; none may be skipped. On other platforms the
Linux-behaviour tests are reported as skipped. The platform tests then assert
the exact refusal on the same fixture that succeeds on Linux, so a blanket
rejection cannot pass. Run the tests as a non-root user, because root can write
any directory and the runtime-root guard would refuse every fixture.
