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
- Audit dependencies for known vulnerabilities using the project's package-manager-native audit command at the declared severity threshold.
- Pin dependency versions.

### Stack-neutral phrasing for dependency-audit references

When citing dependency-audit commands in framework runtime (skills, agents,
commands, templates), use the stack-neutral phrasing:

> «package-manager-native audit command at the declared severity threshold»

Concrete invocations belong in project-level `CLAUDE.md`, not the framework
runtime — they are stack-specific by definition.
<!-- gate:example-only -->
Concrete forms across ecosystems: `npm audit`, `pnpm audit`, `yarn audit`,
`pip-audit`, `cargo audit`, `bundle audit`, `govulncheck`, `composer audit`.
<!-- /gate:example-only -->

Source: TUNE-0043 — emerged 4× as canonical reword across `skills/security.md`,
`skills/project-init.md`, `agents/researcher.md`, `commands/dr-qa.md`. Locking
the phrasing prevents the same reword cycle in future Class A applies.

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

## Cross-Stack Relative-Path Includes (Threat-Model Recipe)

When a task changes the *root* of an HTTP request — flipping `$document_root`, chroot, mount point, container volume, or symlink target — the threat model MUST audit every consumer that resolves paths *relative to that root*, not just the configuration that does the flip.

**Pattern:** any include / require / load directive that resolves a path relative to its own source-file location is bound to its own filesystem location.
<!-- gate:example-only -->
Common forms across ecosystems: `__DIR__`-style anchors, `path.resolve(__dirname, ...)`, `os.path.dirname(__file__)`, `Module::path()` helpers, etc.
<!-- /gate:example-only -->
When the document root flips between two trees that contain *byte-identical files at different inodes*, runtime caches keyed by path (opcode caches, module caches, autoload registries) treat the two paths as different sources, then fail loudly when the same class / module / definition is loaded from both inodes within one worker lifecycle.

**Audit rows to add to STRIDE-style tables for any document_root / chroot / mount-flip task:**

1. *Tampering / Elevation* — cached include from old root remains live in long-running workers after flip → class-redeclare / module-reload error.
2. *Availability* — opcode / bytecode cache primes from one path, new requests resolve to another inode → fatal at request-time.
3. *Repudiation* — the same logical class loaded from two inodes — which one is canonical for audit?

**Mitigation pattern:**

- Make the two roots the same inode tree (symlink one to the other) for the duration of the flip — content equality is not enough; opcache treats path as the cache key.
- Keep absolute paths in critical includes; do not rely on relative-from-source-file resolution at the application boundary.
- Plan a canonical relocation as a follow-up step that severs the symlink dependency.
- Restart any persistent worker pool (long-running request handlers, cached interpreters) to drop stale path bindings — config reload alone is insufficient.

**Source incident:** flipping the request document root for 375 hosts produced fatal `Cannot declare class … already in use` in long-running workers because the application's filesystem-relative include resolved to a different inode under the new root. Auto-rollback fired in <30 s; mitigation = symlink the new root's auxiliary directory to the old root's same directory; canonical relocation deferred to a follow-up step.

## Reusable Templates

- `templates/security-deps-upgrade-plan.md` — stack-neutral plan for dependency-CVE / framework-version-bump / transitive-override tasks. Sections: baseline audit snapshot, target version selection, breaking-change diff, lockfile/peer-dep impact, regression test scope, rollback. Use during `/dr-plan` for any maintenance task closing security advisories.
- `templates/cutover-runbook-template.md` — stack-neutral atomic 8-phase cutover pattern with auto-rollback. Use during `/dr-plan` for any live-service config flip / deployment / mount-point migration where pre/post smoke comparison can guard the change.
