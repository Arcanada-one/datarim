# Security Policy — {{REPO_NAME}}

This repository ships within the Arcanada ecosystem. Vulnerabilities are
triaged under the Arcanada Ecosystem Security Policy Mandate.

## Reporting

Preferred channel for public repositories: **GitHub Private Vulnerability
Reporting** (`Security` tab → `Report a vulnerability`).

Alternative channel: **security@arcanada.one** with subject prefix
`[security]`. Encrypt with the PGP key published on
[keys.openpgp.org](https://keys.openpgp.org) when disclosing exploit
details.

Please do not file public issues for security findings. Reports include:

1. Affected file(s) and version (commit reference if known).
2. Category (e.g. injection, credential exposure, supply-chain
   compromise, workflow bypass).
3. Reproduction — minimal example showing the attack path.
4. Impact assessment — what an attacker gains and at what scope.
5. Suggested fix (optional but appreciated).

## Disclosure SLA

| Stage | Target |
|-------|--------|
| Acknowledgement of report | <= 72 hours |
| Triage and severity assignment | <= 7 days |
| Fix for HIGH / CRITICAL | <= 90 days |
| Fix for MEDIUM | <= 180 days |
| Fix for LOW | best-effort, batched into next minor |
| Coordinated public disclosure | within 14 days of fix, or 120 days after report (whichever sooner), unless embargo is mutually agreed |

If the reporter does not hear back within the acknowledgement window,
they may publicly disclose without further coordination.

## Supported Versions

{{SUPPORTED_VERSIONS_TABLE}}

The repository follows semver. Patch releases are issued for any HIGH
or CRITICAL finding affecting a supported version.

## CI Gate Floor

CI runs the ecosystem reusable security-audit workflow on every pull
request and on push to the default branch:

```yaml
# .github/workflows/ci.yml (consumer side)
jobs:
  security-audit:
    uses: Arcanada-one/datarim/.github/workflows/reusable-security-audit.yml@main
    with:
      stack: {{STACK}}        # typescript_pnpm | rust_cargo | python | framework
      audit_level: high
      accepted_risk_path: accepted-risk.yml
```

The reusable workflow enforces:

1. `SECURITY.md` presence at repo root (fail-closed).
2. `accepted-risk.yml` schema validation when present.
3. Stack-specific dependency audit (advisory database, license check).
4. Cross-check of audit findings against the accepted-risk register —
   unsuppressed and stale-suppressed findings fail the job.

## Accepted Risks

This section is a rendered projection of `accepted-risk.yml` (machine-
readable source-of-truth). Update the YAML file; re-render the table
below on each change.

| Advisory ID | Package | Severity | Scope | Last review | Re-review | Reviewed by | Reason |
|-------------|---------|----------|-------|-------------|-----------|-------------|--------|
| _(no entries)_ | | | | | | | |

Re-review dates MUST satisfy `re_review <= last_review + 90 days`.
Entries past `re_review` raise an ecosystem-wide stale-trigger event
(`warn` at zero days overdue, `fatal` at thirty days overdue).

## Hardening Baseline

This repository enforces:

- Static analysis on shell, configuration, and CI manifests
  (`shellcheck`, `actionlint`, `zizmor`).
- Stack-specific lint, type-check, and test gates declared in
  `.github/workflows/ci.yml`.
- Secret scanning on every push (`gitleaks`).
- Dependency vulnerability scanning per stack profile (invoked through
  the reusable security-audit workflow).
- Branch protection on the default branch: required reviews, required
  status checks, no force-push, no deletions.
- `CODEOWNERS` routing for `SECURITY.md`, `accepted-risk.yml`, and
  `.github/workflows/security*.yml`.

## Standards Mapping

The baseline maps to OWASP ASVS v5, OpenSSF Scorecard, SOC 2 CC,
ISO 27001 Annex A, and CIS Controls v8. Detailed mapping is available
in repository documentation when published.

## Embargo Policy

For pre-disclosure embargoes (e.g. downstream consumers needing time
to patch before public disclosure), email **security@arcanada.one**
with proposed embargo window. Default embargo length is 30 days from
coordinated patch release.

## Hall of Fame

Researchers who responsibly disclose vulnerabilities will be credited
in release notes unless they prefer to remain anonymous.

## Scope

In scope:

- All code shipped in this repository.
- All GitHub Actions workflows under `.github/workflows/`.
- All published release artifacts (when applicable).
- Documentation files that contain executable code blocks.

Out of scope:

- Other ecosystem services — report to that service's own
  `SECURITY.md`.
- Findings that require an attacker to already have full root access
  on the host.
