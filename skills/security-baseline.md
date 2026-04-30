---
name: security-baseline
description: Canonical S1–S9 security rule reference cited from CLAUDE.md § Security Mandate. Load for plan/qa/compliance/do touching shipped artefacts.
---

# Security Baseline (S1–S9)

> **Authority:** RFC 2119 keywords (MUST / MUST NOT / SHOULD / MAY) apply throughout this document.
> **Origin:** corporate security audit, 2026-04-28 — full audit log: [`documentation/archive/security/findings-2026-04-28.md`](../documentation/archive/security/findings-2026-04-28.md). Research baseline: `~/arcanada/datarim/insights/INSIGHTS-security-baseline-oss-cli-2026.md`.
> **Companion skills:** [`skills/security.md`](security.md) (operational recipes — git history scrub, Tailscale+VPN coexistence, recon-vs-compromise heuristics, cross-stack relative-path includes) and [`skills/release-verify.md`](release-verify.md) (S4 consumer-side verify entry point).
> **CI baseline:** [`tests/security/baseline.json`](../tests/security/baseline.json) — machine-readable suppressions registry + required-jobs status.
> **Standards mapping:** [`docs/standards-mapping.md`](../docs/standards-mapping.md) (S8 — full ASVS / SOC 2 / ISO 27001 / CIS table).

---

## Quick reference

| Cluster | Scope                                    | Required CI gate                                       |
|---------|------------------------------------------|--------------------------------------------------------|
| **S1**  | Shell scripts + embedded shell blocks    | `shellcheck` (committed `.sh`)                         |
| **S2**  | Python + python-fenced blocks            | `bandit -ll -ii`                                       |
| **S3**  | Credentials, secrets, tenant identifiers | `gitleaks`, `trufflehog`                               |
| **S4**  | Supply chain                             | `actionlint`, `zizmor`, `osv-scanner`, signed releases |
| **S5**  | Markdown documentation as code           | regex anti-pattern grep (`markdown-policy`)            |
| **S6**  | Repo hygiene (LICENSE, SECURITY.md, …)   | manifest presence checks                               |
| **S7**  | CI verification gate (this matrix)       | meta — every required job above blocks merge           |
| **S8**  | Standards mapping (S1–S7 → ASVS/SOC 2/…) | (no automated gate — informative)                      |
| **S9**  | Drift, evolution, incident response      | `bats` regression tests + suppression registry sync    |

---

## Threat model

Datarim ships skills, templates, agents, and commands that AI agents copy into runtime and execute, often with elevated privileges (root SSH, OAuth tokens with write scope, package installation). A vulnerable line in a shipped script is replicated into every consumer's production runbook. A documented `curl | bash` recipe in a skill becomes the canonical install pattern across the ecosystem. **Every shipped artefact is production code under attack.**

The kill chain to defend against:

1. A skill teaches an unsafe pattern (intentionally as a counter-example, accidentally as boilerplate, or via copy-paste from a stale source).
2. An AI agent loads the skill verbatim into a consumer project's runtime.
3. The consumer project ships the inherited pattern to production.
4. A single CVE / CL / SSRF / leaked token in the shipped recipe compromises every consumer at once.

The baseline therefore optimises for **shipped-artefact correctness** over local convenience. A relaxation that is fine in a one-off project becomes a one-shot ecosystem-wide vulnerability when shipped through Datarim.

---

## S1 — Shell scripts and embedded shell blocks

**Applies to:** every `*.sh` file, every <code>```bash</code> / <code>```sh</code> / <code>```shell</code> fenced block in `skills/`, `agents/`, `commands/`, `templates/`, `docs/`, every `templates/*.sh.j2`-style scaffold.

### Required rules (MUST)

1. **Strict mode** at the top of every script: `set -euo pipefail` and a quoted `IFS=$'\n\t'` (the latter MAY be omitted in non-loop scripts; if omitted, document why inline).
2. **Quote every parameter expansion** (`"$1"`, `"${var}"`, `"$@"` not `$@`). Unquoted expansion is a defect, not a style choice.
3. **Validate positional arguments** (`$1..$N`) against an explicit regex before use:
   ```bash
   if ! [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; then
       echo "Invalid argument: $1" >&2; exit 2
   fi
   ```
4. **Heredoc terminators MUST be quoted** (`<<'EOF'`) to suppress shell expansion when the heredoc carries variables that must reach the consumer literally (e.g. installer recipes, snippet generators). Unquoted heredocs (`<<EOF`) are allowed only when expansion is the explicit intent — document inline.
5. **No `eval`** on user-controlled or filesystem-derived input.
6. **No `curl | bash`** install recipes. Hash-pinned tarballs or package-manager installs only. See S4 for supply-chain detail.
7. **No `ssh -o StrictHostKeyChecking=no`** in any canonical recipe. Bootstrap host keys via `ssh-keyscan -H "$host" >> ~/.ssh/known_hosts` and document key-rotation policy.
8. **`shellcheck -S warning` clean** for committed `*.sh`. Suppression via `# shellcheck disable=...` MUST cite reason + finding-ID + reviewer in an adjacent comment (see § Suppression policy).

### MUST NOT

- Embed `set -e` without `-u` and `-o pipefail` (silent unset-var bugs).
- Use `cd` without `cd "$dir" || exit 1` (or strict-mode equivalent).
- Pipe-source untrusted content into a shell (`bash <(curl ...)` is `curl | bash` in disguise).

### Counter-example fence demonstration

The pattern below is **wrong** — it is shown only to make the corrected version below it intelligible. Production recipes never use this form:

<!-- security:counter-example -->
```bash
# WRONG — unquoted, unvalidated, eval-on-input.
target=$1
eval "rsync -avz $target user@host:/tmp/"
```
<!-- /security:counter-example -->

Corrected form:

```bash
target="$1"
if ! [[ "$target" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "Invalid target path: $target" >&2; exit 2
fi
rsync -avz -- "$target" user@host:/tmp/
```

### CI coverage

- **Required:** `shellcheck` (over committed `*.sh`).
- **Informational (TUNE-0048 promotion path):** `shellcheck-extracted` (over `bash` / `sh` / `shell` blocks extracted from shipped `.md`).

---

## S2 — Python and python-fenced blocks

**Applies to:** every `*.py` file shipped in `code/datarim/` and every <code>```python</code> fenced block in shipped artefacts.

### Required rules

1. **No `subprocess.run(..., shell=True)`** on filesystem-derived or user-controlled input. Pass arguments as a list. If `shell=True` is unavoidable for a documented reason, sanitise via `shlex.quote()` and document the threat-model justification inline.
2. **Atomic credential writes** — when persisting tokens, API keys, or session material to disk, use `os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)` followed by `os.fdopen` and an atomic rename. Never `open(path, "w")` for credential material — the default mode leaks via mode-0644 racing readers.
3. **No `eval` / `exec`** on untrusted input.
4. **No `pickle.loads`** on data that did not originate from a trusted local source. No `yaml.load` without `Loader=yaml.SafeLoader`.
5. **`requests` calls MUST set `verify=True`** (the default) — explicit `verify=False` is forbidden in shipped artefacts.
6. **Hashing** — SHA-256 minimum for new code. MD5 / SHA-1 only when the underlying protocol mandates it (and document the mandate).
7. **`bandit -ll -ii` clean** for committed `*.py`.

### Counter-example fence demonstration

<!-- security:counter-example -->
```python
# WRONG — shell=True with f-string, mode 0644 token write, verify=False.
import requests, subprocess
token = requests.get(url, verify=False).text
subprocess.run(f"echo {token} > /tmp/cred.txt", shell=True)
```
<!-- /security:counter-example -->

Corrected:

```python
import os, requests
resp = requests.get(url, timeout=10)  # verify=True by default
resp.raise_for_status()
fd = os.open("/tmp/cred.txt", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(resp.text)
```

### CI coverage

- **Required:** `bandit -ll -ii` (high+medium severity, high+medium confidence).
- **Informational:** `bandit-extracted` (over `python` blocks extracted from shipped `.md`).

---

## S3 — Credentials, secrets, tenant identifiers

### Required rules

1. **No hardcoded credentials** in any shipped artefact — keys, tokens, OAuth client IDs, tenant IDs, customer-specific URLs, internal IPs.
2. **Generic env-var paths** for credential discovery: `${PROJECT_CREDS_DIR}/<service>/<file>` is the canonical reference shape in shipped templates. Project-specific locations live in the project's `CLAUDE.md`, not in framework runtime.
3. **Secrets sources** in declared order of preference: secret manager / Vault → process environment → operator prompt. **Never:** committed file, command-line argument visible to `ps`, container build-arg.
4. **`.gitignore` coverage** — every shipped template's deployment recipe MUST list candidate secret-bearing paths (`.env`, `*.pem`, `*.key`, `*.token`, `**/Credentials/**`).
5. **Rotation policy on accidental commit** — within 24h: rotate at the issuing system, scrub git history (see [`skills/security.md`](security.md) § Git History Scrub Recipe), force-push, notify clones, document the incident in `documentation/archive/security/`.
6. **Never log** secrets, full tokens, full bearer headers, full session IDs. Redact to first 8 chars + last 4 chars at most for debugging.

### Cross-references

- [`skills/security.md`](security.md) § Git History Scrub Recipe — post-leak rotation playbook.
- `templates/security-deps-upgrade-plan.md` — vault rotation cadence template.

---

## S4 — Supply chain

### Required rules

1. **No `curl | bash`** install recipes anywhere — neither prescribed nor demonstrated outside a counter-example fence.
2. **Hash-pinned installs** — direct downloads MUST verify SHA-256 against a checksum sourced from a separate channel (release notes, signed manifest, official mirror). Do not derive the checksum from the same URL as the artefact.
3. **GitHub Actions pinned to commit SHA** — never tag-pinned (`@v4`), never branch-pinned (`@main`). Each `uses:` line MUST resolve to a 40-char SHA, with a comment naming the human-readable version for auditability.
4. **Explicit `permissions:` block** at workflow or job level — least privilege by default (`permissions: { contents: read }`), elevate only where required.
5. **SBOM** — every release tarball ships a CycloneDX or SPDX SBOM enumerating dependency tree at build time.
6. **Signed releases** — release artefacts MUST be cosign-signed (keyless OIDC preferred). Consumer-side verify recipe: [`docs/release-verification.md`](../docs/release-verification.md) (canonical) + [`skills/release-verify.md`](release-verify.md) (AI-agent loadable entry point).
7. **SLSA Level 2 provenance** — release workflow MUST emit `actions/attest-build-provenance` attestation linkable to the source commit.
8. **Dependency monitoring** — Dependabot or Renovate MUST be configured for the repo; advisories at the declared severity threshold block merge.

### Implementation reference

- Release workflow: [`.github/workflows/release.yml`](../.github/workflows/release.yml) — TUNE-0050 implementation.
- Verify recipe (consumer-side): [`docs/release-verification.md`](../docs/release-verification.md), [`skills/release-verify.md`](release-verify.md).
- Stack-agnostic phrasing for dependency-audit references: see [`skills/security.md`](security.md) § Stack-neutral phrasing.

### Counter-example fence demonstration

<!-- security:counter-example -->
```bash
# WRONG — three S4 violations in two lines.
curl -sSL https://example.com/install.sh | bash
gh actions install @main --no-verify
```
<!-- /security:counter-example -->

Corrected: download the tarball, verify SHA-256 against a separately-sourced checksum, install from the verified tarball. Pin the GitHub Action to a 40-char commit SHA.

---

## S5 — Markdown documentation as executable instructions

**Applies to:** every shipped `.md` (skills, agents, commands, templates, docs, README, CLAUDE.md). The premise: AI agents and humans both treat shipped Markdown as executable knowledge — copy-paste-able, prescriptive.

### Required rules

1. **Placeholders, not real IDs** — examples MUST use `<PLACEHOLDER>`, `${ENV_VAR}`, or obviously synthetic strings (`example.com`, `acme-corp`). Real OAuth client IDs, real tenant IDs, real internal hostnames in shipped docs are S3 violations.
2. **Never prescribe an unsafe pattern** outside a counter-example fence. A skill that says "this is the canonical install — `curl | bash`" silently authorises every consumer to ship that recipe. Reword OR fence.
3. **Counter-example fence syntax is mandatory** for any block teaching what NOT to do (see canonical syntax below).
4. **Scope-aware claims** — a skill that names a stack (NestJS, Django, etc.) MUST live behind `<!-- gate:example-only -->` or be relocated to a project's `CLAUDE.md`. Framework runtime stays stack-agnostic per [`skills/evolution/stack-agnostic-gate.md`](evolution/stack-agnostic-gate.md).

### Counter-example fence syntax (canonical)

For the rare case when a skill / agent / command / template MUST teach an anti-pattern (the wrong way is required to make the right way intelligible), wrap the offending block:

```
<!-- security:counter-example -->
<offending pattern — code fence, snippet, or paragraph>
<!-- /security:counter-example -->
```

Rules:

1. The fence MUST surround the **entire** offending block.
2. The offending block MUST be immediately followed (within the same section) by the corrected pattern.
3. CI gates (`shellcheck-extracted`, `bandit-extracted`, regex anti-pattern grep) MUST be configured to skip blocks between fences.
4. The fence is for **teaching**, not for permanent suppression — production recipes never use it.
5. Distinct from the `<!-- gate:example-only -->` fence (stack-agnostic gate fence — for stack-specific tool names, not for unsafe patterns). Never substitute one for the other.

### `<!-- gate:example-only -->` fence (cross-reference)

Used for stack-specific examples inside framework runtime artefacts. See [`skills/evolution/stack-agnostic-gate.md`](evolution/stack-agnostic-gate.md). Distinct in **purpose** from the security counter-example fence; they MAY co-occur but never substitute for each other.

---

## S6 — Repo hygiene

Every shipped repo (Datarim itself + every consumer project the framework scaffolds) SHOULD ship:

- `LICENSE` — explicit licence, no ambiguity. Stale or absent licence blocks ecosystem use.
- `SECURITY.md` — disclosure policy, security contact, supported version window, embargoed-disclosure timeline.
- `CODE_OF_CONDUCT.md` — community baseline (default: Contributor Covenant or equivalent).
- `CONTRIBUTING.md` — contribution flow, DCO / sign-off requirement if applicable, link to S1–S9 baseline expectations.
- `CODEOWNERS` — review enforcement for sensitive paths: `.github/workflows/`, release scripts, secret-bearing configs, security policies.
- `.github/dependabot.yml` (or Renovate equivalent) — dependency monitoring (S4 obligation). At minimum: weekly check, grouped updates per ecosystem, security-only on `main`.
- **Branch protection** on the default branch — required reviewers ≥1, required status checks (every required S7 job), no force-pushes, no deletes, linear history MAY be required.
- **Tag protection** — semantic-version tags MUST be protected to prevent silent retag after release. SLSA provenance (S4) is invalidated by retags; the protection rule MUST be enforced at the repository host level, not just by convention.

### Sample `.github/dependabot.yml` shape

The shipped baseline (`templates/security-workflow.yml` family) carries a Dependabot stub; consumer projects extend the manifest list to match their stack. The minimum shape:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      actions:
        patterns: ["*"]
```

Consumer projects add their language ecosystem (e.g. one `package-ecosystem` block per dependency manifest). Datarim itself ships only the `github-actions` ecosystem block — the framework has no language manifests in scope.

`templates/security-workflow.yml` is the canonical drop-in for consumer projects. Reusable workflow path: `Arcanada-one/datarim/.github/workflows/reusable-security.yml@<tag>` (preferred — single source of truth, version-pinned).

---

## S7 — CI verification gate

**Required jobs** (block merge):

| Tool          | Scope                                           | S* coverage          |
|---------------|-------------------------------------------------|----------------------|
| `shellcheck`  | committed `*.sh`                                | S1                   |
| `bandit`      | committed `*.py`                                | S2                   |
| `semgrep`     | bash + python + secrets rule packs              | S1, S2, S3           |
| `gitleaks`    | full git history secrets scan                   | S3                   |
| `trufflehog`  | verified-secrets diff scan                      | S3                   |
| `actionlint`  | GitHub Actions workflows                        | S4                   |
| `zizmor`      | GitHub Actions security audit                   | S4                   |
| `osv-scanner` | dependency advisories (when manifests present)  | S4                   |
| `bats`        | regression tests for findings                   | S9                   |
| markdown-policy | regex anti-pattern grep on shipped `.md`      | S5                   |

**Informational jobs (continue-on-error: true)** — promote to required when illustrative blocks are tagged with the appropriate fence:

| Tool                  | Scope                                         | Promotion trigger          |
|-----------------------|-----------------------------------------------|----------------------------|
| `shellcheck-extracted`| bash blocks extracted from shipped `.md`      | prior incident — illustrative-block tagging sweep |
| `bandit-extracted`    | python blocks extracted from shipped `.md`    | prior incident — same           |

Promotion path: tag each illustrative block with the appropriate counter-example or example-only fence, flip `continue-on-error: false`, then the informational job becomes required.

---

## S8 — Standards mapping

Each S* cluster maps to ≥1 control in OWASP ASVS v5 / SOC 2 CC / ISO 27001:2022 Annex A / CIS Controls v8. The full table lives in [`docs/standards-mapping.md`](../docs/standards-mapping.md) — that document is repo-only (not installed to runtime) because the table is too large for inline reading and AI agents fetch it on demand when scoping certification work.

The mapping is **informative**, not certificative — Datarim baseline is a developer-tool floor; consumer projects layer their own application-level baseline on top.

---

## S9 — Drift, evolution, incident response

### Required rules

1. **No relaxation without architect approval** — softening any S1–S8 rule in shipped artefacts requires explicit architect-agent sign-off, recorded in `documentation/archive/security/triage-YYYY-MM.md`.
2. **New finding → rule update + regression test within 7 days** — a security finding (internal audit, external report, CVE in dependency, incident postmortem) MUST produce either (a) a rule clarification in this document with a `tests/security/finding-<N>-<slug>.bats` regression test, or (b) an explicit accepted-risk entry in `tests/security/baseline.json` § `suppressions[]` with reason, expiry, and reviewer.
3. **Suppression registry has authority** — `tests/security/baseline.json` § `suppressions[]` is the canonical record of every active suppression. CI validates that every inline `# shellcheck disable=...`, `# nosec`, `# nosemgrep` marker has a corresponding entry.
4. **Evolution proposals route through `/dr-archive` Step 0.5** — see [`skills/reflecting.md`](reflecting.md) and the Class A/B gate in [`skills/evolution.md`](evolution.md). Class A applies to rule-text expansion (this doc); Class B applies to operating-model change (out of S9 scope).

### Incident response template

Triage doc location: `documentation/archive/security/triage-YYYY-MM.md`. Required sections per incident:

1. **Timeline** — first ingress, detection, confirmed scope, mitigation deployed, all-clear (UTC ISO timestamps).
2. **Scope** — which shipped artefacts touched; which consumer projects inherit them; which versions are affected.
3. **Kill-chain trace** — entry vector → privilege used → blast radius → containment boundary.
4. **Mitigation deployed** — exact commits / tag / version rolled out; rotation steps performed; verification recipe.
5. **Regression test ID** — `tests/security/finding-<N>-<slug>.bats` filename and what it asserts.
6. **Follow-up backlog items** — task IDs for any work deferred, with concrete triggers for closure.
7. **Lessons** — single section feeding back into S1–S9 rule expansion or `tests/security/baseline.json` § `suppressions[]` if accepted-risk.

Reference: SEC-0001 archive — public framework repo carried a leaked OAuth Client ID for 11 days; the recovery added `git filter-repo` two-flag form + pre-push grep gate to [`skills/security.md`](security.md) § Git History Scrub Recipe. The template above is the postmortem shape used by SEC-0001.

---

## Suppression policy (cross-cutting)

Suppression markers (`# shellcheck disable=...`, `# nosec`, `# nosemgrep: <rule>`, `# noqa`, etc.) are **escape hatches**, not bypasses. Every active suppression MUST satisfy:

| Field                    | Required content                                                       |
|--------------------------|------------------------------------------------------------------------|
| **Reason**               | One-line rationale citing why the rule is incorrect or inapplicable    |
| **Scope**                | Inline (single line) preferred; block-scoped only when unavoidable    |
| **File:line citation**   | Recorded in `tests/security/baseline.json` § `suppressions[]`         |
| **Expiry**               | Calendar date OR triggering event (e.g. "until next dependency bump") |
| **Reviewer**             | Architect-agent or named human reviewer                                |

### Marker forms (canonical)

- **shellcheck:** `# shellcheck disable=SC2086 # reason: deliberate word-splitting per S1 exception, reviewer: <name>, expires: 2026-12-31`
- **bandit:** `# nosec B602 # reason: shell=True required for inherited PATH, sanitised via shlex.quote at line N, reviewer: <name>`
- **semgrep:** `# nosemgrep: <rule-id> -- <one-line reason>` (matches existing `templates/cloudflare-nginx-setup.sh` form per `tests/security/baseline.json`)

### Review cadence

- **Inline review** — every suppression added in a PR MUST be flagged in PR description + reviewed alongside the change.
- **Quarterly sweep** — full pass over `tests/security/baseline.json` § `suppressions[]`: confirm reviewer still active, expiry not passed, marker still pinned at the cited line. Stale suppressions MUST either be re-justified or removed.
- **Trigger events** — new audit finding, dependency bump that supersedes a suppressed rule, marker line drift detected by CI.

### Escape-hatch abuse signals

Watch for:

1. Suppressions added in the same PR that introduces the violation, with no separate review thread.
2. Reasons that say "false positive" without citing the specific input that exposes the false positive.
3. Bulk suppressions (`# shellcheck disable=all` or equivalent) — never permitted in shipped artefacts.
4. Suppressions that survive past their expiry without re-justification — quarterly sweep catches these.
5. Suppressions cloned across files via copy-paste without re-evaluating context — each suppression is local to its file:line and reasoning does not transfer automatically.
6. Multi-rule suppressions on a single line (`# shellcheck disable=SC2086,SC2046,SC2128`) where the reason addresses only one rule — the unaddressed rules are silently waived.

### Worked example — accepted suppression

Concrete entry shape in `tests/security/baseline.json` § `suppressions[]` (mirrors the existing form for `templates/cloudflare-nginx-setup.sh`):

```json
{
  "tool": "semgrep",
  "rule": "bash.lang.security.ifs-tampering.ifs-tampering",
  "file": "templates/cloudflare-nginx-setup.sh",
  "line": 28,
  "reason": "canonical strict-mode IFS, not derived from input — defensive, not vulnerable",
  "marker": "# nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering -- canonical strict-mode IFS, not derived from input"
}
```

Every active suppression has a corresponding `suppressions[]` entry; CI validates the marker text matches the registry, the file:line is current, and no unregistered markers exist in the tree.

---

## Relationship to skills/security.md

[`skills/security.md`](security.md) (132 LoC) — **operational recipes** for real-world incidents:

- Git history scrub (post-leak rotation, `--replace-text + --replace-message` two-flag form, pre-push grep gate)
- Tailscale + VPN coexistence (macOS, daemon ordering, `--accept-dns=false`)
- Reconnaissance vs compromise heuristics (200-response noise vs true compromise indicators)
- Cross-stack relative-path includes (chroot / mount-flip threat model recipe)
- Stack-neutral phrasing for dependency-audit references

Loaded on demand when investigating incidents or planning operational responses.

`skills/security-baseline.md` (this document) — **canonical rule reference**. Loaded by reviewer / security agents during /dr-plan, /dr-qa, /dr-compliance touching shipped artefacts; loaded by developer during /dr-do that ships a new skill / agent / template / script.

Both skills cross-link freely; neither replaces the other. CLAUDE.md § Security Mandate cites THIS document as «single source of truth» — that scope is **rules**. Operational recipes (how to scrub history, how to debug Tailscale+VPN) continue to live in `security.md`.

---

## Reusable Templates

- [`templates/security-workflow.yml`](../templates/security-workflow.yml) — drop-in CI gate for consumer projects (TUNE-0045 baseline).
- [`templates/security-deps-upgrade-plan.md`](../templates/security-deps-upgrade-plan.md) — stack-neutral plan for dependency-CVE / framework-bump tasks. See [`skills/security.md`](security.md) § Reusable Templates.
- `tests/security/finding-<N>-<slug>.bats` — regression test scaffold (S9 obligation: every fixed finding gets a regression test).

---

## Source artefacts

- Corporate audit, 2026-04-28: [`documentation/archive/security/findings-2026-04-28.md`](../documentation/archive/security/findings-2026-04-28.md)
- Audit baseline (machine-readable): [`tests/security/baseline.json`](../tests/security/baseline.json)
- Research baseline: `~/arcanada/datarim/insights/INSIGHTS-security-baseline-oss-cli-2026.md` (575 LoC OSS CLI security research, 2026-04-28)
- Recovery archive (incident → rule expansion): SEC-0001 archive at `documentation/archive/security/archive-SEC-0001.md`
- Companion operational recipes: [`skills/security.md`](security.md)
- Consumer-side verify entry: [`skills/release-verify.md`](release-verify.md), [`docs/release-verification.md`](../docs/release-verification.md)
- Standards mapping (S8): [`docs/standards-mapping.md`](../docs/standards-mapping.md)
