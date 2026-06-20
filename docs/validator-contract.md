# Validator Contract (machine-readable)

Canonical exit-code and JSON-shape reference for Datarim framework validators
that participate in the spec-traceability layer. Adopting this one contract
keeps the validators composable: `/dr-verify`'s deterministic floor can re-emit
their findings without reshaping, and CI / pre-commit can branch purely on exit
code without parsing prose.

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Valid / clean — no violations. |
| `1`  | Violations found (hard mode). In `--advisory` mode this is suppressed to `0`. |
| `2`  | Usage or **configuration** error. |

A configuration error (exit `2`) is **never** reported as "0 violations". The
distinction matters: a mis-configured rule set (unknown rule id, an empty
effective set after `--rules`/`--ignore` filtering, or an attempt to disable a
mandatory rule) is a setup failure, not a clean pass. Conflating the two would
let a broken invocation masquerade as success and silently skip enforcement.

## Output format

`--format json` (machine) emits **JSONL** on stdout — one finding object per
line. `--format text` (default) emits a human-readable table. Never parse the
text stream; it is for humans only and is not a stable surface.

### Finding schema

Each JSONL record mirrors the `dev-tools/dr-verify-floor.sh` finding schema so a
floor integration can remap with a single field rename:

```json
{
  "finding_id": "F-spec-1",
  "source_layer": "spec-lint",
  "artifact_ref": "PRD-EXAMPLE-0001.md:42",
  "ac_criteria": ["V-AC-2"],
  "severity": "error",
  "category": "completeness",
  "evidence": { "type": "absent", "source": "PRD-...md:42", "excerpt": "..." },
  "check_name": "covers-resolves"
}
```

- `severity` ∈ `error | warning | info` (registry-driven). The floor maps
  `error → high`, `warning → medium`, `info → low` when re-emitting.
- `category` ∈ `correctness | completeness | consistency | safety`.
- `evidence.type` ∈ `file_quote | test_output | absent`.
- `source_layer` is fixed to `spec-lint` for the spec validators; the floor
  re-stamps it to `floor` on re-emit.

## Common flags

Every spec validator accepts the shared flag vocabulary from
`scripts/lib/spec-graph.sh`:

| Flag | Purpose |
|------|---------|
| `--format json\|text` | Output shape (default `text`). |
| `--task <ID>` | Target task id (resolves PRD / plan / expectations). |
| `--root <path>` | Workspace root override (else walk up to find `datarim/`). |
| `--report` / `--report-file <path>` | Human report toggle / sink. |
| `--dry-run` | Build the graph, report nothing, exit `0`. |
| `--advisory` | Emit findings but always exit `0` (rollout window). |
| `--scope all\|git-diff` | Limit to artefacts changed vs `origin/main`. |
| `--rules a,b` / `--ignore c,d` | Subset / suppress rules (registry-validated). |

## Strict mode

Validators use `set -uo pipefail` — **not** `-e`. A single malformed finding
must never silence the rest of the loop; explicit guards handle non-zero
sub-command exits. The aggregate exit code is the count-or-class outcome, not
the first sub-command failure.

## Shared library

The contract is implemented once in `scripts/lib/spec-graph.sh`
(`emit_finding`, `usage_die`, `parse_common_flags`, `load_rules`,
`effective_ruleset`, graph helpers). Validators source it; they do not
re-implement the contract.
