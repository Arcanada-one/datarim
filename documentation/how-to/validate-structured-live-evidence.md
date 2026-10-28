# Validate structured live evidence

Use the structured evidence checker when a task already has a frozen contract and an evidence bundle, and you need to check their identity, scope, stage order, and recorded results. The checker validates recorded evidence; it does not run the commands named in the bundle or establish task acceptance or runtime behavior.

## Before you start

- Use the accepted `dev-tools/check-live-evidence.sh` and its `dev-tools/lib/live-evidence.sh` from the Datarim runtime tree. Do not copy either file into the project being checked.
- Set the project root to the Git checkout named by the contract. The runtime tool tree and project root are separate locations.
- Keep the contract and evidence bundle already established for the task. The contract binds the task metadata, workflow route, criteria, cases, and scope. Do not create replacement evidence just to make a check pass.
- The accepted behavioral fixture is `tests/evidence_loop_cases.py`. It creates a temporary synthetic Git project with its own contract, metadata, and evidence bundle. It is a fixture, not evidence about a live project or runtime.
- Ensure `python3`, `jq`, `git`, and either `sha256sum` or `shasum` are available. The checker reads the project and evidence; it does not execute evidence commands.

Set paths from the locations supplied by the task environment:

```bash
Datarim_RUNTIME="/path/to/accepted/datarim"
PROJECT_ROOT="/path/to/task/project"
CONTRACT="/path/to/frozen/contract.json"
EVIDENCE="/path/to/recorded/evidence.json"
CHECKER="$Datarim_RUNTIME/dev-tools/check-live-evidence.sh"
```

Run the pre-work check before implementation. If the contract scope changes during work, take a new snapshot; do not replace the original preflight receipt.

```bash
bash "$CHECKER" --root "$PROJECT_ROOT" --contract "$CONTRACT" \
  --evidence "$EVIDENCE" --stage preflight

# Only when a current scope snapshot is needed:
bash "$CHECKER" --root "$PROJECT_ROOT" --contract "$CONTRACT" \
  --evidence "$EVIDENCE" --stage snapshot
```

For a work stage, use a stage that is present in the contract's workflow route. The checker accepts `do`, `write`, `edit`, `publish`, `qa`, `compliance`, `archive`, and `quick` as route stages. `preflight` and `snapshot` are baseline operations, not workflow route entries. A route itself must satisfy the contract's workflow rules.

```bash
bash "$CHECKER" --root "$PROJECT_ROOT" --contract "$CONTRACT" \
  --evidence "$EVIDENCE" --stage qa
```

Choose the stage that matches the evidence already recorded. For example, do not use `qa` merely to ask whether work is complete: the bundle must contain the earlier required stages and QA evidence. `archive` and `quick` additionally require terminal evidence to cover every contract case.

## Read the result

Capture stdout, stderr, and the process exit status separately when retaining a run record. With the default output:

| Exit | Meaning | Default output |
|------|---------|----------------|
| `0` | The requested baseline or stage check completed. | `preflight` and `snapshot` print a JSON receipt to stdout. A work-stage check prints a JSON result with `verdict: "STAGE_PASS"` and any pending cases. |
| `1` | The checker refused the evidence or its currentness. | A `BLOCKED:` reason is written to stderr. Fix or re-establish the named source boundary, then capture a new run; preserve the old receipt and evidence. |
| `2` | Invocation or required-tool usage error. | Usage text is written to stderr. Correct the command or environment before interpreting evidence. |

An exit `0` means only that this structural check passed for the requested stage and observed inputs. It does not prove that recorded commands really ran, that a live runtime behaved as recorded, that the work passed another stage, or that a person accepted the task.

When the checker refuses, use its reason to inspect the named boundary:

- For a missing, changed, invalid, or mismatched contract, confirm the task binding and use the contract established before work. Do not rewrite it to fit the evidence.
- For a changed Git revision, scope, input, task metadata, or evidence file, determine which source changed and whether the task requires a fresh check or a new authorized evidence attempt. Never relabel stale evidence as current.
- For an invalid stage or missing stage evidence, check the workflow route and chronology. Supply only evidence that was actually collected for the required stage.
- For a failed or incomplete case, preserve the recorded result and investigate that case. A refusal is not repaired by removing a criterion or copying another case's result.
- For path, symlink, or artifact identity refusals, inspect the referenced path and recorded digest. Keep evidence within the project root; do not bypass the path check.
- If a required tool is missing or the command is malformed, repair the invocation or environment; a usage error says nothing about whether the task evidence is valid.

## Keep legacy inspection separate

Invocations using the legacy `--expectations` and `--qa-report` options, without the structured flags, print `UNCERTIFIED` to stderr and run the older marker inspection. That mode can report only its legacy marker result. It is not a structured contract check and cannot certify an active task. Do not combine a legacy result with a structured receipt or describe either result as task acceptance.

## Source behavior

- [`check-live-evidence.sh`](../../dev-tools/check-live-evidence.sh)
- [`live-evidence.sh`](../../dev-tools/lib/live-evidence.sh)
- [Behavioral fixture](../../tests/evidence_loop_cases.py)
