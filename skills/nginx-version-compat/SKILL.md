---
name: nginx-version-compat
description: Probe the running nginx version before writing config, then map directive syntax to that version. Load in /dr-plan for any nginx-touching task.
---

# Nginx Version Compatibility

Inline checklist for `/dr-plan` on any task that edits nginx config. Nginx changes directive syntax across releases, so a plan MUST pin the target version first.

## 1. Probe the running version (do this first)

```bash
ssh <host> 'nginx -v'          # prints "nginx version: nginx/1.MM.p" to stderr
ssh <host> 'nginx -V 2>&1 | tr " " "\n" | grep -- --with'   # compiled-in modules (http_v2, http_v3)
```

Record the exact `1.MM.p` in the plan. Never assume — distros pin old branches (Debian bookworm ships 1.22.x, Ubuntu 22.04 ships 1.18.x).

## 2. Version to syntax mapping

| Feature | up to 1.25.0 (legacy) | 1.25.1 and later (modern) |
|---|---|---|
| HTTP/2 | `listen 443 ssl http2;` | `listen 443 ssl;` plus a separate `http2 on;` |
| HTTP/3 / QUIC | unavailable (before 1.25.0) | `listen 443 quic reuseport;` plus `http3 on;` (needs `--with-http_v3_module`) |

`http2` and `http3` are standalone directives, not `listen` parameters, from 1.25.1 onward; the old `listen ... http2` form is deprecated and warns on 1.25.1+.

## 3. Common breaking-change traps

- `quic` / `http3` require nginx built `--with-http_v3_module` (absent from most distro packages) — confirm via `nginx -V` before planning HTTP/3.
- `ssl_protocols` and cipher defaults differ by build; state them explicitly rather than relying on defaults.
- Reload safely: `nginx -t` (config test) MUST pass before `nginx -s reload`.
