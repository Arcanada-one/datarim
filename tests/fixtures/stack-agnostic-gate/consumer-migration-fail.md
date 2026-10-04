---
name: fixture/consumer-migration-fail
description: Golden FAIL fixture — stack-specific migration and package-manager recipes. Gate MUST exit 1.
---

# Golden FAIL fixture — stack-specific migration and package-manager recipes

These three negative examples pin stack-specific instructions so a future
regression is caught by the gate before application to framework runtime.

## Artefact 1 — security.md fetch migration

Replace the legacy `axios` HTTP client with the native `fetch` API (Node 18+).
`fetch` removes a transitive dependency surface and aligns with the WHATWG
standard. Existing axios call sites can be migrated incrementally per service.

## Artefact 2 — Dependency Safety multi-PM list

For each language ecosystem, declare the package-manager security gate:

- Node: `npm audit --omit=dev --audit-level=high`
- Python: `pip-audit --strict`
- Rust: `cargo audit --deny warnings`
- Ruby: `bundle audit check`
- Go: `go mod audit` (or third-party `govulncheck`)

Pin gate threshold in CI; fail the build on any unresolved high/critical CVE.

## Artefact 3 — Live Audit Checkpoint recipes

Before /dr-do, materialise dependencies in `/tmp/dr-plan-audit-{TASK-ID}/`:

```
pnpm install --prod
pnpm audit --prod --audit-level=high
```

Or for Python:

```
pip install -r requirements.txt
pip-audit --strict
```

If the gate fails, bump pins or record an accepted-risk sign-off in the plan.
