# QA Charter

> Create one charter for each task before verification work begins. Replace
> every placeholder and keep the single JSON block valid. The charter defines
> probes; the evidence bundle records what was actually observed.

The charter owner is accountable for maintaining the behaviour contract and
resolving coverage gaps. Each behaviour names its contract, risk, real
entrypoint, isolation boundary, exit condition, source, commands, inputs,
applicable surfaces, and required probes.

```qa-charter-json
{
  "schema": "DatarimQaCharter/v1",
  "owner": "<person or accountable role>",
  "behaviours": [
    {
      "id": "<stable-behaviour-id>",
      "contract": "<observable behaviour and durable effect>",
      "risk": "<failure impact>",
      "entrypoint": "<real user or system entrypoint>",
      "isolation": "<fixture, account, service, and state boundary>",
      "exit_condition": "<falsifiable completion condition>",
      "source": "<implementation or authoritative contract paths>",
      "commands": ["<exact verification command>"],
      "inputs": ["<synthetic or otherwise authorized input>"],
      "surfaces": ["cli"],
      "probes": [
        {
          "id": "<stable-probe-id>",
          "surface": "<one listed surface>",
          "required": true,
          "description": "<one falsifiable assertion>"
        }
      ]
    }
  ]
}
```

The JSON block above is an unfilled template and must not be used as a task
charter until every placeholder is replaced. A behaviour may list only the
surfaces that apply to it; do not claim a surface was verified merely because
it appears in the vocabulary. Supported surface names are `browser`, `api`,
`cli`, `worker`, and `webhook`.

## Evidence and immutable run baseline

For a task identifier `{TASK-ID}`, store the charter at
`datarim/qa/qa-charter-{TASK-ID}.md`. Store each independent evidence run at
`datarim/qa/qa-charter-{TASK-ID}/run-YYYYMMDDTHHMMSSZ/evidence.json`, alongside
the probe artifacts it names. Create a fresh run directory with an exclusive
`mkdir`; create each file once with exclusive creation. Never reuse a run
directory, overwrite a prior baseline, or refer to a mutable `latest` alias.
The evidence bundle binds the exact charter SHA-256, source revision, run id,
and UTC capture time. The validator is read-only and rejects stale pins,
mutable paths, missing required evidence, and artifact digest drift.

Each probe result records its stable `id`, `outcome`, `observed` result, exact
`command` and `exit_code` when run, and `artifact.path` plus
`artifact.sha256` for retained output. `not run` and `n.a.` require a concrete
`reason`; `n.a.` is allowed only for a probe not marked required. Outcomes are
exactly `pass`, `fail`, `blocked`, `not run`, `inconclusive`, or `n.a.`. A
required probe contributes to coverage PASS only with outcome `pass`.

The bundle uses this shape; replace all placeholders with measured values:

```json
{
  "schema": "DatarimQaCharterEvidence/v1",
  "charter_sha256": "<sha256-of-exact-charter-bytes>",
  "source_revision": "<current-git-HEAD>",
  "run_id": "run-20261018T120000Z",
  "captured_at": "2026-10-18T12:00:00Z",
  "probes": [
    {
      "id": "<required-probe-id>",
      "outcome": "pass",
      "observed": "<actual assertion result>",
      "command": "<exact command>",
      "exit_code": 0,
      "artifact": {
        "path": "<retained-output-file>",
        "sha256": "<sha256-of-retained-output>"
      }
    }
  ]
}
```

## Checkpoint linkage

An ordered array of attempts is not a hypothesis-linked checkpoint chain. If
the evidence format does not define a validated relation from the next probe
to the prior observation and its hypothesis, record checkpoint linkage as
deferred in the task record. Do not infer the relation from chronology alone.

## Validator call path

`/dr-qa` invokes the read-only validator from its charter-coverage subcheck:

```bash
python3 "${DATARIM_RUNTIME:?}/dev-tools/check-qa-charter-coverage.py" \
  --root <repo-root> \
  --charter <repo-root>/datarim/qa/qa-charter-{TASK-ID}.md \
  --evidence <repo-root>/datarim/qa/qa-charter-{TASK-ID}/run-<UTC>/evidence.json
```

Any nonzero result blocks charter coverage. A successful result proves only
that the required probes in the exact charter have current, digest-bound
evidence at the named source revision; it does not prove semantic correctness
beyond those assertions, checkpoint linkage, runtime acceptance, or production
readiness.
