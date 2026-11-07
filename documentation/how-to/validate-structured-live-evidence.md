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

## Optionally capture the maintainer/CI JSON summary

Use this opt-in mode only when a maintainer or CI job needs the versioned summary. It does not change the checker's validation or its process exit codes. Keep `DATARIM_RUNTIME` pointed at the accepted runtime tree and `PROJECT_ROOT` at the checkout named by the contract; keep the new capture directory outside that checkout and its evidence inputs.

The example below creates a private directory before opening any output file. If creation fails or returns no path, it stops before invoking the checker. The checker stdout, checker stderr, and numeric process status are kept separately; the command is not piped through another program.

```bash
set +x
umask 077
: "${DATARIM_RUNTIME:?Set DATARIM_RUNTIME to the accepted runtime tree}"
: "${PROJECT_ROOT:?Set PROJECT_ROOT to the checked-out project root}"
: "${CONTRACT:?Set CONTRACT to the frozen contract file}"
: "${EVIDENCE:?Set EVIDENCE to the recorded evidence bundle}"

CHECKER="$DATARIM_RUNTIME/dev-tools/check-live-evidence.sh"
if ! SUMMARY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/live-evidence-summary.XXXXXX" 2>/dev/null)" \
  || [ -z "$SUMMARY_DIR" ]; then
  printf '%s\n' 'ERROR: could not create private summary directory' >&2
  exit 1
fi

SUMMARY_FILE="$SUMMARY_DIR/live-evidence.json"
CHECKER_STDERR="$SUMMARY_DIR/checker.stderr"
if bash "$CHECKER" --summary-json \
  --contract "$CONTRACT" --evidence "$EVIDENCE" \
  --root "$PROJECT_ROOT" --stage qa \
  >"$SUMMARY_FILE" 2>"$CHECKER_STDERR"; then
  checker_exit=0
else
  checker_exit=$?
fi
```

`qa` is an example; choose a stage already present in the contract's workflow route and supported by the recorded evidence. The local setup failure above is the recipe's own error, not checker exit `1` or `2`. For the checker, retain its actual exit separately: `0` may mean a preflight/snapshot receipt or `STAGE_PASS`, `1` means `BLOCKED`, and `2` means `USAGE_ERROR` or a handled dependency/usage refusal. Summary mode normally writes one JSON object for its handled result. A launch failure, signal before emission, or broken output stream can leave the file absent or incomplete; that is not a valid summary and must not be interpreted as a checker verdict.

Read the file with a JSON parser, require one object whose `schema` is `datarim.live-evidence-summary/v1`, and check that its `exit_code` agrees with the captured process status before using other fields. Keep the process status and object fields distinct. The documented fields are `verdict`, fixed `reason_code`, `stage`, `identity`, and `counts`; each count and `identity.source_revision` has an `availability` marker and a `value`. `availability: "AVAILABLE"` with value `0` is a measured zero. `availability: "NOT_MEASURED"` with value `null` is unavailable, not zero. See the [summary reference](../../dev-tools/README.md#live-evidence-json-summary-maintainerci-only) for the complete field and reason-code contract.

This consumer checks the version, result kind, and agreement between the file and process status before reporting a fixed, safe message. For a valid summary, `SystemExit(process_exit)` makes the recipe process preserve the checker status (`0`, `1`, or `2`); the existing job policy remains responsible for deciding what to do with that result. Invalid or absent output stops with the explicit capture error instead. The consumer does not print summary contents or define a new gate:

```bash
python3 - "$SUMMARY_FILE" "$checker_exit" <<'PY'
import json
import sys
from pathlib import Path

def invalid_summary():
    raise SystemExit("ERROR: live-evidence summary is missing or invalid")

try:
    summary = json.loads(Path(sys.argv[1]).read_bytes())
    process_exit = int(sys.argv[2])
except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
    invalid_summary()

if not isinstance(summary, dict):
    invalid_summary()
if summary.get("schema") != "datarim.live-evidence-summary/v1":
    invalid_summary()
if type(summary.get("exit_code")) is not int or summary["exit_code"] != process_exit:
    invalid_summary()

verdict = summary.get("verdict")
allowed = {"PREFLIGHT_RECEIPT", "SNAPSHOT_RECEIPT", "STAGE_PASS", "BLOCKED", "USAGE_ERROR"}
if not isinstance(verdict, str) or verdict not in allowed:
    invalid_summary()
if (process_exit == 0 and verdict not in allowed - {"BLOCKED", "USAGE_ERROR"}) or \
   (process_exit == 1 and verdict != "BLOCKED") or \
   (process_exit == 2 and verdict != "USAGE_ERROR") or process_exit not in {0, 1, 2}:
    invalid_summary()

print(f"Live-evidence result: {verdict}; checker exit: {process_exit}")
if verdict == "STAGE_PASS":
    print("This is a stage-check result, not task or runtime acceptance.")
raise SystemExit(process_exit)
PY
```

Treat empty, malformed, unsupported-version, or process-status-mismatched output as an invalid capture. A valid `BLOCKED` summary is a checker refusal, not an invalid capture; apply the consuming job's existing policy to the retained process status and summary. Do not print the raw JSON, arbitrary diagnostics, contract/evidence content, or filesystem paths into CI logs. A summary or `STAGE_PASS` is not task acceptance, runtime evidence, or customer acceptance, and the checker does not execute the commands recorded in the evidence bundle.

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
