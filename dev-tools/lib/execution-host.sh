#!/usr/bin/env bash
# shellcheck shell=bash
# execution-host.sh — shared, framework-native execution-host resolver
# library (TUNE-0472, Phase 2). Sourceable, no side-effects on source.
#
# One resolver, two consumers:
#   (a) Step-0 "EXECUTION HOST" block in /dr-* commands (cooperative, soft).
#   (b) machine-local PreToolUse guard (dev-tools/datarim-exec-guard.sh in
#       the workspace repo, TUNE-0471 Phase 1 — hard floor, refactored to
#       call this library instead of carrying its own copy of the
#       host-match logic).
#
# Contract mirrors the Phase-1 `lookup_binding` field shape (TAB-separated:
# required_host, host_aliases_csv, tailscale_ip, ssh_user, default_agent,
# allowed_agents_csv, space) so callers can drop this in as a replacement.
#
# Exit-code contract for eh_decision():
#   0   unconfigured (no binding for this workspace) -> fail-open, proceed
#   0   on-host (binding present, current host matches)      -> proceed
#   10  off-host (binding present, current host does NOT match) -> delegate
#   3   fail-closed: malformed YAML, or map unreadable in a way that is
#       NOT simply "no map / no binding" (e.g. yq parse error)
#
# yq degrade rule: if `yq` is not installed, the library cannot read ANY
# map safely, so it degrades to "unconfigured" (return 0, fail-open) rather
# than fail-closed — the absence of the tool is an environment gap, not a
# security signal, and this mirrors Phase-1's `lookup_binding` behaviour
# (`command -v yq >/dev/null 2>&1 || return 1`).
#
# Each function sets its own strict-mode locally and isolates errors into
# its own exit code — sourcing this file must never abort the caller's
# shell (no top-level `set -e` at source time).

# --- eh_resolve_workspace_root ----------------------------------------------
# Walk up from start_dir until an ancestor containing datarim/ is found.
# stdout: the resolved root (no trailing slash). Returns 1 if none found.
eh_resolve_workspace_root() {
    local dir="${1:-}"
    [ -n "$dir" ] || return 1
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -d "$dir/datarim" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# --- eh_lookup_binding -------------------------------------------------------
# Read the YAML bindings map and return the binding for `root`, if any.
# stdout (TAB-separated): required_host, host_aliases_csv, tailscale_ip,
#                         ssh_user, default_agent, allowed_agents_csv, space
# Returns 1 on: missing map, missing yq, no binding for root.
# Returns 3 on: malformed YAML (map exists, yq present, but fails to parse).
eh_lookup_binding() {
    local root="$1" map_path="$2"
    [ -n "$root" ] && [ -n "$map_path" ] || return 1
    [ -f "$map_path" ] || return 1
    command -v yq >/dev/null 2>&1 || return 1

    local n
    if ! n=$(yq e '.bindings | length' "$map_path" 2>/dev/null); then
        return 3
    fi
    case "$n" in
        ''|*[!0-9]*) return 3 ;;
    esac
    [ "$n" -gt 0 ] || return 1

    local i=0
    while [ "$i" -lt "$n" ]; do
        local ws
        ws=$(yq e ".bindings[$i].workspace" "$map_path" 2>/dev/null || true)
        if [ "$ws" = "$root" ]; then
            local host aliases ip user agent allowed space
            host=$(yq e ".bindings[$i].required_host" "$map_path" 2>/dev/null)
            aliases=$(yq e ".bindings[$i].host_aliases | join(\",\")" "$map_path" 2>/dev/null)
            ip=$(yq e ".bindings[$i].tailscale_ip" "$map_path" 2>/dev/null)
            user=$(yq e ".bindings[$i].ssh_user" "$map_path" 2>/dev/null)
            agent=$(yq e ".bindings[$i].default_agent" "$map_path" 2>/dev/null)
            allowed=$(yq e ".bindings[$i].allowed_agents | join(\",\")" "$map_path" 2>/dev/null)
            space=$(yq e ".bindings[$i].space" "$map_path" 2>/dev/null)
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
                "$host" "$aliases" "$ip" "$user" "$agent" "$allowed" "$space"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# --- eh_host_match -----------------------------------------------------------
# Compares the current host against required_host, any comma-separated
# alias, or the tailscale_ip. Returns 0 on match (this host IS the
# execution host), 1 otherwise.
#
# Test override: EH_TEST_HOSTNAME lets bats fixtures pin the "current host"
# without touching the real `hostname`/Tailscale MagicDNS name. Production
# callers never set this var.
eh_host_match() {
    local required_host="$1" aliases_csv="${2:-}" tailscale_ip="${3:-}"
    local current
    if [ -n "${EH_TEST_HOSTNAME:-}" ]; then
        current="$EH_TEST_HOSTNAME"
    else
        current="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
    fi
    [ -n "$current" ] || return 1

    [ "$current" = "$required_host" ] && return 0
    [ -n "$tailscale_ip" ] && [ "$current" = "$tailscale_ip" ] && return 0

    if [ -n "$aliases_csv" ]; then
        local -a aliases
        IFS=',' read -ra aliases <<< "$aliases_csv"
        local a
        for a in "${aliases[@]}"; do
            [ "$current" = "$a" ] && return 0
        done
    fi
    return 1
}

# --- eh_decision -------------------------------------------------------------
# Orchestrator: resolves the workspace root's binding and current-host
# match into a single verdict.
#   0  -> unconfigured (no binding) OR on-host (binding + match): proceed
#   10 -> off-host (binding present, host does not match): delegate
#   3  -> fail-closed (malformed YAML)
eh_decision() {
    local root="$1" map_path="$2"
    local binding rc

    binding="$(eh_lookup_binding "$root" "$map_path" 2>/dev/null)"
    rc=$?

    case "$rc" in
        1) return 0 ;;   # unconfigured: no map / no yq / no binding -> fail-open
        3) return 3 ;;   # malformed YAML -> fail-closed
    esac

    # rc == 0: binding found. Parse the TAB-separated fields.
    local req_host aliases ip user agent allowed space
    IFS=$'\t' read -r req_host aliases ip user agent allowed space <<< "$binding"

    if eh_host_match "$req_host" "$aliases" "$ip"; then
        return 0   # on-host
    fi
    return 10      # off-host
}
