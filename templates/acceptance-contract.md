# Acceptance Contract

Store the machine-readable contract as JSON. A replacement records both
`contract_version` and `supersedes_version`; keep the older version for
case-by-case comparison. Before QA can record PASS, the QA charter declares
the new `contract_version`, covers the replacement's required criteria, and
has a current immutable evidence run. A prior-version charter cannot certify
the replacement.

Each case's `environment` states the observable invariant that must hold
throughout its verification window and the guard that proves it when the case
runs. Record the guard result with the case evidence. A named operational
mechanism alone does not prove the invariant.

```json
{
  "contract_version": "2",
  "supersedes_version": "1",
  "cases": [
    {
      "id": "example-case",
      "environment": {
        "invariant": "No conflicting writer changes the test data during this case",
        "guard": "Check the writer exclusion state before the case and retain its result",
        "verification_window": "From case setup through the final assertion"
      }
    }
  ]
}
```
