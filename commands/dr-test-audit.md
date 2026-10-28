---
name: dr-test-audit
description: Build a read-only report for an explicit bounded test selection
---

# /dr-test-audit

Use this opt-in command when a maintainer supplies a specific test selection and retained evidence for review. It produces a structural report; it does not decide whether tests are semantically redundant or whether any proposed action is correct.

## Inputs

1. Read the selection JSON named by the maintainer, using the schema in [Test Audit Report](../documentation/reference/test-audit-report.md). The selection path must be relative to the declared project root and inside that root.
2. Confirm the selection contains only the intended test files and explicitly listed receipt references. Do not add tests, expand globs, search for evidence, or infer missing observations.
3. Run the builder once with the supplied root and selection:

   ```bash
   python3 "${DATARIM_RUNTIME:?}/dev-tools/build-test-audit-report.py" --root PROJECT --selection SELECTION.json
   ```

4. Preserve its numeric exit status and stdout/stderr. On exit 0, stdout is the versioned JSON report. On nonzero exit, retain the fixed diagnostic code; do not describe an empty or failed report as a result.

## Interpretation

- Treat every `proposed_action` as a user-authored proposal for review, not a tool decision or instruction to change tests.
- Keep each recommendation attached to its selected test source hash, existing five-field Test Value Card and any explicitly cited receipt hashes/pointers.
- `NOT_MEASURED` cost fields mean the selection did not cite a valid observation for that metric. They are not zero and do not support a performance estimate.
- The report validates bounded file and JSON structure. It does not certify card meaning, receipt authenticity, test quality, overlap semantics, production behavior or future cost.

Do not run tests, edit or remove files, lower gates, change a test plan, publish the report or trigger CI from this command. Running, removing or rewriting tests and changing gates require a separate authorized reviewed change.
