# Legacy Hardware Probe Checklist

A reusable 7-step probe checklist for legacy embedded Linux integrations (routers, NAS appliances,
IoT gateways running vendor-frozen firmware). Run this **before** committing to an architectural
approach in `/dr-plan` — a 30-minute probe replaces speculative toolchain assumptions with facts.

Reference: `$HOME/.claude/skills/probing.md`.

---

## Step 1 — CPU Architecture

```bash
uname -m && cat /proc/cpuinfo
```

Confirms actual instruction set (e.g. `armv5l` vs `arm` vs `mips`) — do not infer from vendor marketing copy.

---

## Step 2 — TUN/TAP Device Availability

```bash
test -c /dev/net/tun; echo $?
```

**0**: device node present — userspace VPN tooling (WireGuard-in-userspace, Tailscale userspace mode, etc.)
can attach. **Non-zero**: no TUN device — kernel module missing or disabled; userspace networking will not work
without a firmware change.

---

## Step 3 — Free RAM

```bash
free -m | head -2
```

Legacy appliances often ship with 64–256 MB total RAM. Confirm headroom before adding any long-running
background process.

---

## Step 4 — OpenSSL Version and PBKDF2 Support

```bash
openssl version && openssl enc -pbkdf2 -help 2>&1 | head -1
```

Old firmware frequently bundles `openssl 1.0.2` or earlier, which lacks `-pbkdf2`. Any encryption scheme
that assumes PBKDF2 key derivation must first confirm the flag exists — otherwise fall back to a
vendored/static binary or an alternative KDF.

---

## Step 5 — BusyBox Applet Availability

```bash
busybox --list | grep -E 'nohup|start-stop-daemon|setsid|crontab|crond'
```

Confirms which of the five applets a background-process / cron-based integration needs are actually
compiled into this BusyBox build. A missing `nohup` or `crond` blocks the naive approach and forces an
alternative (e.g. `setsid` substitution, or a persistent init script instead of cron).

---

## Step 6 — Cron Spool Permissions

```bash
ls -la /var/spool/cron/crontabs/
```

Some vendor defaults ship this directory or the `root` crontab world-writable (mode `666`). Treat this as
a security finding — document it, and do not add cron entries without first tightening the permission if
the fix is in scope.

---

## Step 7 — Machine-Identity Sources

```bash
ls -la /etc/zyxel/ 2>/dev/null || find / -xdev -name '*serial*' -o -name '*board*' 2>/dev/null
```

Board-serial files are not guaranteed to exist across vendors/firmware revisions. Confirm an actual
machine-identity source before designing around it — fall back to a MAC-address-derived identity
(`ip link show` / `/sys/class/net/*/address`) when no serial file is present.

---

## Reporting Template

Append to the plan / creative doc:

```markdown
### Legacy Hardware Probe

| Step | Result |
|------|--------|
| 1. CPU architecture | `<uname -m output>` |
| 2. /dev/net/tun | present / absent |
| 3. Free RAM | `<N> MB` |
| 4. OpenSSL PBKDF2 | supported / unsupported (`<version>`) |
| 5. BusyBox applets | `<matched applets>` / missing: `<list>` |
| 6. Cron spool perms | `<mode>` |
| 7. Machine-identity source | board-serial / MAC-derived / none found |

**Architectural implication**: `<one line — which approach the probe results rule in or out>`
```

---

## Anti-Pattern to Refuse

Do not draft an architecture doc for a legacy embedded target from vendor documentation or memory alone.
Vendor docs describe the shipped firmware version at release time, not the specific unit's actual state.
Run this checklist first; let the probe results — not assumptions — drive the design.
