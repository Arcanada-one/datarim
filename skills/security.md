---
name: security
description: Authentication, authorization, input validation, data protection, dependency safety. Use for security review or when handling secrets and user data.
---

# Security Guidelines

## Authentication & Authorization
- Never hardcode secrets/keys. Use `.env`.
- Validate all inputs on the server side.
- Use least privilege principle for API keys.

## Data Protection
- Sanitize all user inputs (prevent XSS/SQLi).
- Encrypt sensitive data at rest and in transit.
- Do not log PII (Personally Identifiable Information).

## Dependency Safety
- Audit dependencies for known vulnerabilities (`npm audit`).
- Pin dependency versions.

## Reconnaissance vs Compromise

A **200 response** to a suspicious filename is **not proof of compromise**. Many sites legitimately host files whose names overlap with common webshell filenames (`dk.php`, `install.php`, `index2.php`). Reconnaissance traffic is constant background noise — every public IPv4 is probed daily.

**Before declaring compromise:**
1. Verify the file is small and matches legitimate site-loader patterns (e.g., 200-500 bytes, includes a common framework bootstrap).
2. Run `strace -p <worker_pid>` on a live request to see what the script actually does.
3. Check file ownership, modification date, and whether it matches the site's provisioning date.
4. Compare hash against other sites on the same server — legitimate boilerplate will be identical across many directories.

**True compromise indicators:**
- File with unusual base64-encoded payloads or `eval($_POST[...])` patterns.
- File size or modification date inconsistent with site provisioning.
- Outbound connections from PHP workers to unknown IPs (check `ss -tnp` on worker PIDs).
- Unexpected cron entries, SSH keys, or suid binaries.

Never confuse scanner noise with successful exploitation. Log scanner IPs for firewall deny lists, but don't escalate based on probe traffic alone.

## Tailscale + VPN Coexistence (macOS)

When a commercial VPN (Wireguard-based or otherwise) coexists with Tailscale on macOS, control-plane and data-plane breakage is common. Order of operations and per-daemon flags matter:

1. **Reboot after any Tailscale version update.** Old system extensions can silently linger and steal the utun interface. `systemextensionsctl list` surfaces ghost kexts.
2. **`--accept-dns=false`** on the Tailscale node if a VPN provides its own DNS. Two daemons both overriding `/etc/resolv.conf` produces intermittent NXDOMAIN.
3. **Start Tailscale BEFORE the VPN.** VPN clients typically claim the first available `utun` index; if Tailscale is second, it may fail to establish the tunnel or route packets through the wrong interface.
4. **Verify the Tailscale utun interface is up** — `ifconfig | grep -A1 utun.*tailscale` should show a non-zero interface and an IPv4 in the `100.64.0.0/10` range before trusting the mesh.
5. **Free auth keys are single-use** — reusing an expired key silently fails. Generate a new key from the admin console for each rejoin.

Source: AGENT-0010 reflection + memory `feedback_macos_tailscale.md`. ~60 min of debug time saved per future incident by following this checklist first.
