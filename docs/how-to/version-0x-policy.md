---
Title: How the 0.x version regime is handled for autonomous releases
Category: How-to (Diátaxis how-to)
---

# How the 0.x version regime is handled for autonomous releases

## Policy statement

For any package whose current version is below 1.0.0 (the **0.x regime**), a change that the structural API-diff tool detects as **breaking** is **always escalated to the operator** and is never published autonomously. This holds even though standard SemVer arithmetic under 0.x would bump the version as a *minor*, not a *major*. The escalation is driven by the **API-diff result**, not by the version number.

Patch and non-breaking minor changes under 0.x **do** flow autonomously, without any operator prompt.

## Rationale

0.x APIs are inherently immature. The project has not yet made a stable contract to consumers. Accidental breaking changes — the most dangerous form of false-negative classification — are most likely to occur exactly here, because the API surface is still being shaped and commit-message hygiene may not be battle-hardened. A single mislabeled commit (e.g., `fix:` for a removal of a public symbol) can ship a breaking change as a patch under 0.x if the gate relies only on commit-message analysis. The human gate on every 0.x breaking change prevents that class of incident.

## Classifier behaviour

The classification script `dev-tools/release-classify.sh` applies the following logic:

1. It reads the current package version and sets `zero_x=true` for any version matching `0.*`.
2. It evaluates the nominal bump from commit-message analysis.
3. It runs the structural API-diff tool when present (`griffe` for Python, `cargo-semver-checks` for Rust). When neither is on PATH it reports `api_diff=unavailable` (see Honest limitation below). npm/TS structural diffing is not wired today — those ecosystems rely on commit-message classification plus the CI surface.
4. It sets `escalate=true` when:
   - the nominal bump is `major`; **OR**
   - `zero_x` is `true` **AND** any breaking change is detected by the API-diff tool (regardless of the nominal bump).

### Honest limitation

When the structural API-diff tool is not available for a given ecosystem — because no reliable tool exists or because it has not been installed in the CI environment — the classifier reports `api_diff=unavailable`. In this state the script **cannot** raise a 0.x minor to an escalation on its own; it can only honour the commit-message-based bump level. The authoritative API-diff surface is therefore the **CI release job**, where the tooling is pinned. The operator must ensure the tool is present in the release pipeline for any 0.x package; otherwise breaking changes may slip through as minor bumps.

## Related documents

- [How to set up a PyPI Trusted Publisher for autonomous first-publish](pypi-first-publish.md) — the one-time bootstrap step every new PyPI package requires before full autonomy can start.
- [How to roll back a failed autonomous release](release-rollback.md) — yank, deprecate, or patch recovery procedures for PyPI, npm, and GitHub Releases.