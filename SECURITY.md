# Security Policy

Datarim is a methodology + tooling framework whose artifacts (skills, agents,
commands, templates) are read and executed by AI agents and human operators on
production systems. A vulnerability in a shipped artifact propagates to every
consumer. Reports are treated accordingly.

## Supported Versions

| Version | Supported |
|---------|-----------|
| `2.x`   | ✅ — latest minor receives all security fixes |
| `1.18.x` and earlier | ❌ — please upgrade to 2.x |

The framework follows semver. Patch releases are issued for any HIGH or
CRITICAL finding affecting the latest minor.

## Reporting a Vulnerability

**Please do not file public GitHub issues for security findings.**

Preferred channel: **GitHub Private Security Advisory**
(`Security` tab → `Report a vulnerability`).

Alternative channel: **mail@veritasarcana.ai** with subject prefix
`[security]`. Encrypt with our public PGP key on
[keys.openpgp.org](https://keys.openpgp.org) if disclosing exploit
details.

Include in the report:

1. Affected file(s) and version (commit SHA if known).
2. Category (e.g. shell injection, credential exposure, supply-chain
   compromise, GHA workflow bypass).
3. Reproduction — minimal example showing the attack path.
4. Impact assessment — what an attacker gains and at what scope
   (single consumer / ecosystem-wide).
5. Suggested fix (optional but appreciated).

## Disclosure SLA

| Stage | Target |
|-------|--------|
| Acknowledgement of report | ≤ 72 hours |
| Triage + severity assignment | ≤ 7 days |
| Fix for HIGH / CRITICAL | ≤ 90 days |
| Fix for MEDIUM | ≤ 180 days |
| Fix for LOW | best-effort, batched into next minor |
| Coordinated public disclosure | within 14 days of fix, or 120 days
  after report (whichever sooner), unless embargo is mutually agreed |

If the reporter does not hear back within the acknowledgement window,
they may publicly disclose without further coordination.

## Embargo Policy

For pre-disclosure embargoes (e.g. enterprise consumers needing time
to patch before public disclosure), email
`mail@veritasarcana.ai` with proposed embargo window. Default
embargo length is 30 days from coordinated patch release.

## Scope

In scope:

- All code shipped in the repository: `skills/`, `agents/`, `commands/`,
  `templates/`, `scripts/`, `dev-tools/`, `install.sh`, `update.sh`,
  `tests/`.
- All GitHub Actions workflows under `.github/workflows/`.
- All published release artifacts (source tarballs, SBOMs, signatures,
  attestations).
- Documentation files that contain executable code blocks
  (`documentation/`, `*.md` at repo root).

Out of scope:

- Consumer projects that *use* the framework — report to that project's
  own security contact.
- The Arcanada ecosystem services (Auth Arcana, Verdicus, etc.) — each
  has its own `SECURITY.md`.
- Findings that require an attacker to already have full root access on
  the host running the framework.

## Hardening Baseline

This repository enforces a security baseline composed of:

- Static analysis: `shellcheck`, `bandit`, `semgrep`, `actionlint`,
  `zizmor` (workflow security).
- Secret scanning: `gitleaks`, `trufflehog` (verified credentials only).
- Vulnerability scanning: `osv-scanner` on package manifests.
- Regression tests: `bats` suite, one test per closed finding under
  `tests/security/`.
- Supply chain: CycloneDX SBOM via `syft`, cosign keyless signing,
  SLSA L2 build provenance attestation on every release.
- Pre-commit: optional local enforcement via `.pre-commit-config.yaml`.
- Repository hardening: pull-request-only integration, required status checks,
  resolved review conversations, no force-push, and no branch deletion; immutable
  release tags; `CODEOWNERS` routing critical paths to the service owner.

See `documentation/how-to/release-verification.md` for downstream consumer verification
recipe and `documentation/how-to/release-process.md` for the maintainer release
playbook.

## Documented Scorecard Limitations

OpenSSF Scorecard findings are remediated when they represent an actionable
control gap. The following repository-shape signals are explicitly accepted and
are re-evaluated on every security release:

- **Token-Permissions / release:** the release job needs `contents: write`,
  `id-token: write`, and `attestations: write` to publish, sign, and attest.
  The workflow default is empty, classification is read-only, dispatch is pinned
  to protected `main`, and the supplied annotated tag is SSH-authenticated and
  required to peel to the exact checked-out SHA before write authority exists.
- **Token-Permissions / Dependabot:** the auto-merge job needs write authority.
  It has no checkout and is bound to the complete trusted event tuple: actor,
  sender, PR author, source repository, base `main`, branch prefix, and canonical
  PR URL.
- **Code-Review:** this owner-operated public framework currently has one
  eligible service author. Pull requests, independent review evidence, required
  checks, and conversation resolution are mandatory; a distinct approval count
  is zero because requiring the same author to self-approve is not an independent
  control.
- **Fuzzing:** the shipped executable surface is shell/Python orchestration with
  bounded text schemas rather than a network parser or native memory-unsafe
  library. Deterministic Bats boundary tests, unsafe fixtures, Semgrep, CodeQL,
  Bandit, and adversarial review provide the proportionate control.
- **CII Best Practices:** a separate OpenSSF Best Practices registration is not
  an execution control for this owner-operated framework. The repository instead
  publishes its security policy, signed releases, SBOM, provenance, tests, and
  live Scorecard evidence directly.

These are accepted limitations, not silent exceptions. Their corresponding
Scorecard alerts may be dismissed only with a reference to this section and
must be reopened if the trust model or executable surface changes.

## Standards Mapping

The baseline maps to OWASP ASVS v5, OpenSSF Scorecard, SOC 2 CC,
ISO 27001 Annex A, and CIS Controls v8. The full mapping is in
`documentation/reference/standards-mapping.md` (when published).

## Hall of Fame

Researchers who responsibly disclose vulnerabilities will be credited
in release notes unless they prefer to remain anonymous.
