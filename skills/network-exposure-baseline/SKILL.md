---
name: network-exposure-baseline
description: Allowlist/blocklist for network bind targets (compose ports, redis bind, postgres listen_addresses, systemd ListenStream); load before any port change.
---

# Network Exposure Baseline

## When To Use

Load THIS skill before any change that touches: `docker-compose` ports / expose; `redis.conf` bind / protected-mode; `postgresql.conf` listen_addresses; systemd `.socket` ListenStream; a bare network listener (a runtime bind argument such as `host=0.0.0.0`); firewall / UFW rules.

NOT for: purely internal refactoring with no networking change; purely application-logic work.

## Why It Matters (founding principle)

Public-by-default = breach-by-default.

Background: in a prior incident in the ecosystem, Redis 7.x listened on `0.0.0.0:6379` without auth and Postgres ran with `listen_addresses='*'` and the default password — both were reachable from the public internet, which led to an abuse report from the regulator. Root cause: docker compose default-binds to `0.0.0.0` and there was no CI/CD gate.

The goal of this baseline: make a restricted bind the default; public exposure is opt-in with a justification and a TTL.

## Tier Model (canonical)

| Tier | Bind targets | Justification | Example |
|---|---|---|---|
| Tier 0 | unix socket / no port published | not required | `/run/redis/redis.sock` |
| Tier 1 | `127.0.0.1`, `::1`, `::ffff:127.0.0.1` | not required | `127.0.0.1:5432` |
| Tier 2 | Tailscale CGNAT `100.64.0.0/10` + `::ffff:100.64.0.0/10` | not required (mesh-only by definition) | `100.65.1.5:5432` |
| Tier 3 | `0.0.0.0`, `::`, public IPs, mapped public IPv6, `*`, `listen_addresses='*'`, **any specific public IPv4**, **RFC1918 private (`10/8`, `172.16/12`, `192.168/16`)**, **link-local (`169.254/16`)** | REQUIRED — `x-exposure-justification` + `x-exposure-expires` (≤90 days) | `203.0.113.10:443`, `192.168.1.50:5432`, `0.0.0.0:443` + Cloudflare ACL |

> **Why specific public AND private IPv4 are both Tier 3.** A static linter cannot read the host routing table, so it cannot prove that a private RFC1918 (or link-local) bind is mesh-only the way a loopback bind is safe-by-construction — a private address bridged onto a public-routed interface is a real exposure. Block-by-default folds all of them into Tier 3: the justification forces a human to record *why* the bind is safe, and the TTL forces re-review. Only loopback and Tailscale CGNAT are pass-by-construction. A genuinely unparseable bind string (not a dotted-quad, not a recognised IPv6) remains `malformed` (exit 2) — distinct from a Tier-3 violation (exit 1), which is a valid bind missing its annotation.

## Decision Tree

Walk this tree for every bind target in the diff.

```mermaid
flowchart TD
    A([Start]) --> B{Port published?}
    B -->|No| C[Tier 0 PASS]
    B -->|Yes| D{Host IP extractable<br/>from bind string?}
    D -->|No / short-form| E[Implicit 0.0.0.0<br/>Tier 3 without justification]
    E --> F[FAIL]
    D -->|Yes| G{Classify IP}
    G -->|127.0.0.1 / ::1 /<br/>::ffff:127.0.0.1| H[Tier 1 PASS]
    G -->|100.64.0.0/10 /<br/>::ffff:100.64.0.0/10| I[Tier 2 PASS]
    G -->|0.0.0.0 / :: / [::] /<br/>* / listen_addresses=*| J[Tier 3]
    G -->|Specific public IPv4| J
    G -->|RFC1918 private /<br/>169.254 link-local| J
    G -->|Other mapped IPv6| J
    G -->|Other IPv6| J
    G -->|Not an IP at all| F
    J --> K{Justification + TTL valid?<br/>expires ≤90d, in future}
    K -->|Yes| L[Tier 3 PASS]
    K -->|No| F
```

## Allowlist (verbatim)

These targets are allowed with no extra justification.

- `127.0.0.1`
- `::1`
- `::ffff:127.0.0.1`
- `100.64.0.0/10` (Tailscale CGNAT)
- `::ffff:100.64.0.0/10` (mapped Tailscale)
- unix socket paths (anything starting with `/`, ending with `.sock`)

## Blocklist (default deny)

Anything not in the allowlist and without a valid justification is denied by default.

- `0.0.0.0`
- `::` / `[::]` / `0:0:0:0:0:0:0:0`
- `*`
- `listen_addresses = '*'`
- `bind 0.0.0.0`
- `ListenStream=0.0.0.0` / `[::]`
- short-form ports (for example `"5432:5432"`, `"6379"`) — implicit `0.0.0.0`
- Dockerfile `EXPOSE` without host context — emit warn, do not fail by default

## Justification format

Tier 3 requires an explicit exposure justification.

### Primary — YAML extension (docker-compose)

```yaml
services:
  api:
    ports:
      - "0.0.0.0:443:443"
    x-exposure-justification: "Public HTTPS endpoint behind edge ACL + rate-limit"
    x-exposure-expires: "YYYY-MM-DD"
```

### Fallback — inline comment (non-compose)

```
# exposure: justified expires=YYYY-MM-DD — short reason
bind 100.64.1.5
```

### TTL rule

- Mandatory for Tier 3.
- The `expires` date MUST be in the future and ≤90 days from the file's last modification date.
- Missing or expired (when required) → FAIL.
- Rationale: waivers accumulate and are forgotten; the TTL forces a quarterly review.

## Compose variable interpolation (`${VAR}` in a bind host)

A docker-compose bind host is often a shell-style parameter expansion — e.g. a mesh bind `${TAILNET_IP:?tailnet ip required}:443:443`. The linter reads the string verbatim (it never shell-expands it) and resolves it with the **B3 hybrid** strategy, in order:

1. **env-resolve** — if the named environment variable is set, its value is classified. (Resolution is `printenv`-only; the value is never executed.)
2. **default-extract** — for the `${VAR:-D}` / `${VAR-D}` forms with the variable unset, the default literal `D` is classified. So `${BIND_HOST:-0.0.0.0}` with no env is a Tier-3 violation, and `${BIND_HOST:-127.0.0.1}` passes.
3. **unresolved residual** — for `${VAR:?msg}` or bare `${VAR}` with the variable unset and no default, the linter emits a **WARN naming the variable + `file:line` and PASSES** (exit 0). It cannot know the runtime value in CI where the variable is intentionally unset, and false-failing every legitimate mesh bind would make the linter a CI nuisance.

**Recommendation:** for a required mesh variable use the `${VAR:?reason}` form — it both documents intent and forces compose itself to fail fast if the variable is missing at deploy time. Avoid `${VAR:-default}` where the default would classify into a different (weaker) tier than the intended runtime value.

**Residual accepted risk.** An unresolved `${UNKNOWN_PUBLIC_IP}` passes with a WARN even if its runtime value would be a public bind. The residual is *deliberate, greppable, and reviewer-visible*: every such WARN names the variable and `file:line`, so a reviewer scanning the linter output sees exactly which binds were accepted unresolved. Resolve the variable in the environment (or pin it via `:-default`) to get a hard classification.

**Security boundary.** The `${...}` body is untrusted compose input. The variable name is regex-validated (`^[A-Za-z_][A-Za-z0-9_]*$`) as the trust boundary before any environment read; resolution is `printenv`-only — no `eval`, no `source`, no indirect expansion, no shell expansion. A token whose body carries command-substitution or shell metacharacters (`$(...)`, backtick, `;`, `|`, `&`, `<`, `>`) is rejected outright as an injection attempt (violation, exit 1) and is never resolved.

## Examples Gallery

<details>
<summary>8 side-by-side cases (compose syntax)</summary>

1. **PASS**: `127.0.0.1:5432:5432` (Tier 1)
2. **PASS**: `100.65.1.5:5432:5432` (Tier 2 Tailscale)
3. **PASS**: `[::1]:5432:5432` (Tier 1 IPv6)
4. **PASS**: `0.0.0.0:443:443` + valid justification + expires (Tier 3 justified)
5. **FAIL**: `0.0.0.0:6379:6379` — no justification (Tier 3 unjustified)
6. **FAIL**: `5432:5432` — short-form (implicit Tier 3)
7. **FAIL**: `0.0.0.0:443:443` + expires=2025-01-01 (expired)
8. **FAIL**: `[::]:5432:5432` (IPv6 unspecified)

</details>

## Anti-patterns

<details>
<summary>Common mistakes that trigger FAIL</summary>

- Short-form ports in `docker-compose` without a host-IP.
- Justification text without a description of the actual mitigation (for example just "because we have to").
- Pushing `expires` far into the future (>90 days) to bypass review.
- `listen_addresses='localhost,*'` (mixed allow + deny).
- `bind 0.0.0.0` in production Redis under the excuse "it's inside Docker network".
- Allow only Cloudflare IPs but without confirming that the origin is unreachable directly.

</details>

## Verifier Integration

Verification program: `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-check.sh"` parses `docker-compose.yml` / `redis.conf` / `postgresql.conf` / systemd `.socket`; reads `x-exposure-justification` + `x-exposure-expires`; applies the classification from this skill. Drift between the skill and the script is a defect — update both at the same time.

Invocation:

```bash
"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-check.sh" --compose path/to/docker-compose.yml
```

Exit codes:

- `0` — clean
- `1` — violation
- `2` — usage error

## Pipeline Integration (forward reference)

This skill is consumed by:

- `/dr-prd` — a Network Exposure Baseline section is mandatory in the PRD (Tier declaration plus justifications for Tier 3).
- `/dr-plan` — warning if the plan touches networking surfaces without an explicit Tier classification.
- `/dr-do` — pre-commit-style check on the diff: new `0.0.0.0`, short-form ports, no `# exposure: justified` → block.
- `/dr-archive` — validation-checklist gate: every Tier 3 bind has an unexpired justification.

## Tiered Gate Rules (canonical decision table)

Pipeline commands read the task-description frontmatter and pick one of three decisions: `hard_block` (the gate blocks the step), `advisory_warn` (the gate prints a warning but does not block), `skip` (the gate is silent). Decision table:

| Priority | Type                                                                                    | Network surface touched? | Decision        |
|----------|-----------------------------------------------------------------------------------------|--------------------------|-----------------|
| `P0`     | (any)                                                                                   | (any)                    | `hard_block`    |
| `P1`     | `security-incident` / `infrastructure` / `infra` / `framework-hardening` / `security-baseline` / `auth-mandate` | (any)         | `hard_block`    |
| `P1`     | others                                                                                  | (any)                    | `advisory_warn` |
| `P2`/`P3`| (any)                                                                                   | yes                      | `advisory_warn` |
| `P2`/`P3`| (any)                                                                                   | no                       | `skip`          |
| missing/malformed | —                                                                              | —                        | `hard_block` (fail-closed) |

"Network surface touched" means that the diff (for `/dr-plan`) or the staged change (for `/dr-do`) touches one of the verifier's sources: docker-compose, `redis.conf`, `postgresql.conf`, systemd `.socket`, firewall / UFW rules, or a runtime bind argument.

The canonical executor is `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh"`. Drift between this skill and the script is a defect — update both at the same time. Every gate decision is reported as telemetry to Ops Bot (`category: info, agent: dr-prd|dr-plan|dr-do|dr-archive, body: gate=<decision> task=<id>`) for quarterly tuning via `/dr-optimize`.

Example invocation from a pipeline command:

```bash
# nosec-extract
decision=$("${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh" \
    --task-description datarim/tasks/<TASK-ID>-task-description.md \
    --network-diff \
    --quiet)
case "$decision" in
    hard_block)    # STOP pipeline step
        ;;
    advisory_warn) # print warning, continue
        ;;
    skip)          # silent
        ;;
esac
```

## Machine-parseable Rules Block

```yaml
allowlist:
  - 127.0.0.1
  - ::1
  - ::ffff:127.0.0.1
  - 100.64.0.0/10
  - ::ffff:100.64.0.0/10
blocklist:
  - 0.0.0.0
  - '::'
  - '*'
  - listen_addresses='*'
  - bind 0.0.0.0
  - 'ListenStream=0.0.0.0'
short_form_ports: deny    # docker-compose 'ports' entries without a host-IP component
unix_socket: allow
ttl_max_days: 90
justification_required_tiers: [3]
expired_justification: deny
```

## References

- `security-baseline.md` — Datarim Security Mandate (S1–S9), pre-commit gate.
- `file-sync-config.md` — pre-flight checklist style template.
- CIS Docker Benchmark — Docker container hardening.
- NIST SP 800-204 — service security baseline.
- OWASP Cloud Top 10.
