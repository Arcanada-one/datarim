---
name: network-exposure-baseline
description: Allowlist/blocklist for network bind targets (compose ports, redis bind, postgres listen_addresses, systemd ListenStream); load before any port change.
---

# Network Exposure Baseline

## When To Use

Загружай ЭТОТ skill перед любым изменением, которое затрагивает: `docker-compose` ports/expose; `redis.conf` bind/protected-mode; `postgresql.conf` listen_addresses; systemd `.socket` ListenStream; bare network listener (runtime bind argument, например `host=0.0.0.0`); firewall/UFW rules.

NOT для: чисто внутреннего рефакторинга без сетевых изменений; чисто прикладной логики.

## Why It Matters (founding principle)

Public-by-default = breach-by-default.

Background: в ecosystem предыдущего инцидента Redis 7.x слушал `0.0.0.0:6379` без auth, а Postgres имел `listen_addresses='*'` с дефолтным паролем — оба были доступны из интернета, что привело к abuse report от регулятора. Корневая причина: docker compose default bind `0.0.0.0` и отсутствие CI/CD gate.

Цель этой baseline: сделать ограниченный bind дефолтом; публичная экспозиция — opt-in с обоснованием и TTL.

## Tier Model (canonical)

| Tier | Bind targets | Justification | Example |
|---|---|---|---|
| Tier 0 | unix socket / no port published | not required | `/run/redis/redis.sock` |
| Tier 1 | `127.0.0.1`, `::1`, `::ffff:127.0.0.1` | not required | `127.0.0.1:5432` |
| Tier 2 | Tailscale CGNAT `100.64.0.0/10` + `::ffff:100.64.0.0/10` | not required (mesh-only by definition) | `100.65.1.5:5432` |
| Tier 3 | `0.0.0.0`, `::`, public IPs, mapped public IPv6, `*`, `listen_addresses='*'` | REQUIRED — `x-exposure-justification` + `x-exposure-expires` (≤90 days) | `0.0.0.0:443` + Cloudflare ACL |

## Decision Tree

Следуй дереву для каждого bind-target в diff.

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
    G -->|Other mapped IPv6| J
    G -->|Other IPv6| J
    G -->|Malformed| F
    J --> K{Justification + TTL valid?<br/>expires ≤90d, in future}
    K -->|Yes| L[Tier 3 PASS]
    K -->|No| F
```

## Allowlist (verbatim)

Эти target'ы разрешены без дополнительного обоснования.

- `127.0.0.1`
- `::1`
- `::ffff:127.0.0.1`
- `100.64.0.0/10` (Tailscale CGNAT)
- `::ffff:100.64.0.0/10` (mapped Tailscale)
- unix socket paths (anything starting with `/`, ending with `.sock`)

## Blocklist (default deny)

Всё, что не входит в allowlist и не имеет валидного justification, по умолчанию запрещено.

- `0.0.0.0`
- `::` / `[::]` / `0:0:0:0:0:0:0:0`
- `*`
- `listen_addresses = '*'`
- `bind 0.0.0.0`
- `ListenStream=0.0.0.0` / `[::]`
- short-form ports (например `"5432:5432"`, `"6379"`) — implicit `0.0.0.0`
- Dockerfile `EXPOSE` без host context — emit warn, don't fail by default

## Justification format

Для Tier 3 требуется явное обоснование экспозиции.

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

- Обязательно для Tier 3.
- Дата `expires` должна быть в будущем и ≤ 90 дней от даты модификации файла.
- Отсутствует или просрочена (когда требуется) → FAIL.
- Обоснование: waiver'ы накапливаются и забываются; TTL принудительно инициирует quarterly review.

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

- Short-form ports в `docker-compose` без host-IP.
- Justification text без описания фактической mitigation («потому что надо»).
- Перенос `expires` далеко в будущее (>90 дней) для обхода review.
- `listen_addresses='localhost,*'` (смешанный allow + deny).
- `bind 0.0.0.0` в production redis под предлогом «это же в Docker network».
- Allow Cloudflare-only IPs, но без подтверждения, что origin недоступен напрямую.

</details>

## Verifier Integration

Программа верификации: `dev-tools/network-exposure-check.sh` парсит `docker-compose.yml` / `redis.conf` / `postgresql.conf` / systemd `.socket`; читает `x-exposure-justification` + `x-exposure-expires`; применяет classification из этого skill. Drift между skill и script — defect; обновляй обе одновременно.

Запуск:

```bash
dev-tools/network-exposure-check.sh --compose path/to/docker-compose.yml
```

Exit codes:

- `0` — clean
- `1` — violation
- `2` — usage error

## Pipeline Integration (forward reference)

Этот skill используется командами:

- `/dr-prd` — обязательная секция Network Exposure Baseline в PRD (Tier declaration + justifications для Tier 3).
- `/dr-plan` — warning, если план меняет networking surfaces без явной Tier-классификации.
- `/dr-do` — pre-commit-style check на diff: новые `0.0.0.0`, short-form, без `# exposure: justified` → block.
- `/dr-archive` — validation checklist gate: все Tier 3 binds имеют unexpired justification.

## Tiered Gate Rules (canonical decision table)

Pipeline-команды читают frontmatter task description и принимают одно из трёх
решений: `hard_block` (gate блокирует шаг), `advisory_warn` (gate печатает
предупреждение, но не блокирует), `skip` (gate тих). Decision table:

| Priority | Type                                                                                    | Network surface touched? | Decision        |
|----------|-----------------------------------------------------------------------------------------|--------------------------|-----------------|
| `P0`     | (любой)                                                                                  | (любой)                  | `hard_block`    |
| `P1`     | `security-incident` / `infrastructure` / `framework-hardening` / `security-baseline` / `auth-mandate` | (любой)         | `hard_block`    |
| `P1`     | прочие                                                                                   | (любой)                  | `advisory_warn` |
| `P2`/`P3`| (любой)                                                                                  | yes                      | `advisory_warn` |
| `P2`/`P3`| (любой)                                                                                  | no                       | `skip`          |
| missing/malformed | —                                                                              | —                        | `hard_block` (fail-closed) |

«Network surface touched» означает, что diff (для `/dr-plan`) или staged change
(для `/dr-do`) затрагивает один из источников verifier'а: docker-compose,
`redis.conf`, `postgresql.conf`, systemd `.socket`, firewall/UFW rules, или
runtime bind argument.

Канонический исполнитель — `dev-tools/network-exposure-gate.sh`. Drift между
этим skill'ом и скриптом — defect; обновляй обе одновременно. Каждое решение
гейта эмитится телеметрией в Ops Bot (`category: info, agent: dr-prd|dr-plan|dr-do|dr-archive, body: gate=<decision> task=<id>`) для quarterly tuning через `/dr-optimize`.

Пример вызова из pipeline-команды:

```bash
# nosec-extract
decision=$(dev-tools/network-exposure-gate.sh \
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
short_form_ports: deny    # docker-compose 'ports' entries без host-IP части
unix_socket: allow
ttl_max_days: 90
justification_required_tiers: [3]
expired_justification: deny
```

## References

- `security-baseline.md` — Datarim Security Mandate (S1–S9), pre-commit gate
- `file-sync-config.md` — pre-flight checklist style template
- CIS Docker Benchmark — Docker container hardening
- NIST SP 800-204 — service security baseline
- OWASP Cloud Top 10