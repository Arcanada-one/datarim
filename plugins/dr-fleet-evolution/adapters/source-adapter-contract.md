# Source-adapter contract

A source-adapter reads execution signals from one origin and emits them as a
uniform **eval dataset** in JSONL. The evolution loop merges the output of every
registered adapter into a single dataset that drives variant generation and
candidate scoring.

## Interface

- **Invocation:** `adapter.sh <source-path>` — `argv[1]` is a directory or file
  the adapter reads. Adapters MUST NOT read any path other than the one passed.
- **stdout:** JSONL — one JSON object per line, each conforming to the schema
  below. No trailing prose, no banner lines.
- **Exit codes:**
  - `0` — success (stdout may be empty when the source holds no signals; an
    empty source is **not** an error).
  - non-zero — a parse or I/O error the loop must surface (the loop warns and
    continues with the remaining adapters).

## Record schema

Each JSONL line is a JSON object with exactly these fields:

```json
{
  "task_input": "string",
  "expected_output": "string",
  "actual_output": "string",
  "outcome": "success",
  "source": "archive"
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `task_input` | string | What the unit of work was asked to do |
| `expected_output` | string | The intended/ideal result (may be empty when unknown) |
| `actual_output` | string | What actually happened |
| `outcome` | `"success"` \| `"failure"` | Whether the unit of work met its goal |
| `source` | string | Adapter label (e.g. `archive`, `dr-dream`) |

## Registration (extension-point)

Adapters are listed in `source-adapters.conf`, one per line:

```
<path-to-adapter-script>|<source-path>|<label>
```

Adding a line activates a new adapter in the next loop run. No code change to the
loop is required — this is the extension-point for future sources (e.g. the
deferred audit-log adapter, a tracked follow-up).

## Security

Adapter output is fed to an external LLM via `coworker`. Adapters MUST only read
public knowledge-base artefacts (archive records, reflection notes). Sources that
may carry sensitive traces (paths, hostnames, command fragments, secrets) require
a redaction layer before they are eligible — see the tracked follow-up.
