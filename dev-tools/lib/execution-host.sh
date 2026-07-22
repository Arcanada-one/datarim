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

# ============================================================================
# TUNE-0507 — RESILIENCE layer: canon-fallback + intent-aware fail-closed.
#
# The functions below are ADDITIVE. eh_decision() above is a pure resolver used
# by on-host Step-0 callers and is left byte-for-byte unchanged (its 0/10/3
# contract + the 16 execution-host.bats cases must not regress). The new
# intent-aware verdict lives in eh_decision_intent().
#
# Why canon-fallback: eh_decision() returns 0 ("unconfigured") for BOTH «this
# workspace has no execution mandate» (legit fail-open) AND «the machine-local
# cache is simply absent/stale on a machine that SHOULD be gated». On the
# execution host itself the cache is routinely ABSENT, yet that host IS the
# correct one — a naive "unconfigured + mutating -> fail-closed" would brick all
# legitimate on-host mutating work. Resolving the workspace's space against
# CANON (spaces/<space>/space.yml § execution) when the cache has no binding
# makes "unconfigured" mean "canon truly has no execution mandate", which both
# fixes that trap (canon -> resolve on-host -> allow) and makes the
# fail-open -> fail-closed flip safe.
# ============================================================================

# --- eh_canon_space_for_root -------------------------------------------------
# Resolve the space that GOVERNS this workspace root from the git-tracked
# registry (spaces/registry.yml -> the `role: root-managing` entry — the space
# that manages this very workspace). Space-agnostic: never hardcodes a name.
# stdout (TAB-separated): <canon_space.yml_path>\t<space_name>
# Returns 1 when: no registry / no yq / no root-managing entry / no space.yml.
eh_canon_space_for_root() {
    local root="$1"
    [ -n "$root" ] || return 1
    local reg="$root/spaces/registry.yml"
    [ -f "$reg" ] || return 1
    command -v yq >/dev/null 2>&1 || return 1
    local name
    name=$(yq e '.registry[] | select(.role == "root-managing") | .name' "$reg" 2>/dev/null | head -n1)
    [ -n "$name" ] && [ "$name" != "null" ] || return 1
    local canon="$root/spaces/$name/space.yml"
    [ -f "$canon" ] || return 1
    printf '%s\t%s' "$canon" "$name"
    return 0
}

# --- eh_lookup_binding_canon -------------------------------------------------
# Canon-side counterpart of eh_lookup_binding: reads the governing space's
# `execution:` block directly from committed canon. Emits the SAME 7-field TAB
# shape as eh_lookup_binding (required_host, host_aliases_csv, tailscale_ip,
# ssh_user, default_agent, allowed_agents_csv, space).
# Canon layout tolerance mirrors check-execution-host-drift.sh: a top-level
# `execution:` (real space.yml) or a nested `space.execution:` are both read.
# Returns 1 on: no governing space / canon absent / no required_host (canon
#               truly carries no execution mandate).
# Returns 3 on: malformed canon YAML (yq parse error).
eh_lookup_binding_canon() {
    local root="$1"
    [ -n "$root" ] || return 1
    command -v yq >/dev/null 2>&1 || return 1
    local pair canon name
    pair="$(eh_canon_space_for_root "$root")" || return 1
    IFS=$'\t' read -r canon name <<< "$pair"
    [ -f "$canon" ] || return 1

    local host
    if ! host=$(yq e '(.execution // .space.execution).required_host // ""' "$canon" 2>/dev/null); then
        return 3
    fi
    [ -n "$host" ] && [ "$host" != "null" ] || return 1   # canon has no mandate

    local aliases ip user agent allowed
    aliases=$(yq e '(.execution // .space.execution).host_aliases // [] | join(",")' "$canon" 2>/dev/null)
    ip=$(yq e '(.execution // .space.execution).tailscale_ip // ""' "$canon" 2>/dev/null)
    user=$(yq e '(.execution // .space.execution).ssh_user // ""' "$canon" 2>/dev/null)
    agent=$(yq e '(.execution // .space.execution).default_agent // ""' "$canon" 2>/dev/null)
    allowed=$(yq e '(.execution // .space.execution).allowed_agents // [] | join(",")' "$canon" 2>/dev/null)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$host" "$aliases" "$ip" "$user" "$agent" "$allowed" "$name"
    return 0
}

# --- eh_canon_mandate_present ------------------------------------------------
# yq-FREE presence probe: does ANY spaces/<name>/space.yml under this workspace
# carry an execution mandate? Grep-only so it still answers when yq is ABSENT
# (the exact condition under which eh_lookup_binding_canon degrades to "return
# 1"). This is what separates «truly unconfigured» (fail-OPEN) from «a mandate
# exists but the tooling cannot resolve the host» (fail-CLOSED for mutating).
# Deliberately coarse and conservative: if a mandate exists anywhere in the
# workspace's spaces/ tree we cannot prove on-host without yq, so we treat the
# machine as one that SHOULD be gated. Returns 0 = present, 1 = absent.
eh_canon_mandate_present() {
    local root="$1"
    [ -n "$root" ] || return 1
    local d="$root/spaces"
    [ -d "$d" ] || return 1
    local f
    for f in "$d"/*/space.yml; do
        [ -f "$f" ] || continue
        if grep -Eq '^[[:space:]]*(execution:|required_host:)' "$f" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# --- eh_classify_intent ------------------------------------------------------
# Coarse read-only vs mutating classifier for a (heredoc/quote-stripped) command
# string. Only a tiny, unambiguous read-only /dr-* allowlist is treated as
# readonly; everything else (mutating /dr-*, opaque claude/codex agent
# invocations, raw branch/worktree-creation) defaults to `mutating`. Fail-safe:
# an unknown shape is mutating, so the fail-closed policy errs toward blocking.
# stdout: `readonly` | `mutating` (always exit 0).
eh_classify_intent() {
    local cmd="$1"
    case " $cmd " in
        *"/dr-status"*|*"/dr-help"*) printf 'readonly'; return 0 ;;
    esac
    printf 'mutating'
    return 0
}

# --- eh_decision_intent ------------------------------------------------------
# Intent-aware verdict with canon-fallback. Same host resolution as eh_decision,
# extended so an UNREADABLE map fails CLOSED for mutating intent while staying
# fail-OPEN for read-only and for the legitimately-unconfigured case.
#   0  -> proceed (on-host, OR truly unconfigured, OR ANY read-only intent)
#   10 -> off-host (a binding — cache or canon — resolves elsewhere): delegate
#   3  -> fail-closed (mutating intent + map/canon unreadable while a mandate
#         exists, OR malformed YAML): the machine cannot prove it is on-host
# intent: `mutating` (default) | `readonly`.
#
# Read-only intent is fail-open THROUGHOUT: an observational command never
# mutates state, so it is always allowed locally (dispatching it buys nothing)
# — the short-circuit below is the single source of that guarantee, so every
# gating branch afterwards is reached only for mutating intent.
eh_decision_intent() {
    local root="$1" map_path="$2" intent="${3:-mutating}"
    local binding rc req aliases ip

    [ "$intent" = "readonly" ] && return 0

    # --- mutating intent from here on ---------------------------------------
    binding="$(eh_lookup_binding "$root" "$map_path" 2>/dev/null)"
    rc=$?

    case "$rc" in
        3) return 3 ;;   # malformed cache map -> fail-closed
        0)               # cache hit -> host-match decides
            IFS=$'\t' read -r req aliases ip _ _ _ _ <<< "$binding"
            eh_host_match "$req" "$aliases" "$ip" && return 0
            return 10
            ;;
    esac

    # rc == 1: cache miss / degraded (no map / no yq / no binding). Fall back to
    # committed canon so a merely-absent cache does not read as "unconfigured".
    local cbind crc
    cbind="$(eh_lookup_binding_canon "$root" 2>/dev/null)"
    crc=$?
    case "$crc" in
        0)  # canon resolves the binding -> host-match decides (FIXES the trap)
            IFS=$'\t' read -r req aliases ip _ _ _ _ <<< "$cbind"
            eh_host_match "$req" "$aliases" "$ip" && return 0
            return 10
            ;;
        3) return 3 ;;   # malformed canon YAML -> fail-closed
    esac

    # crc == 1: canon carries no resolvable binding via yq. Distinguish «no
    # mandate at all» (fail-open) from «mandate exists but yq is absent /
    # unreadable» (fail-closed).
    eh_canon_mandate_present "$root" && return 3   # mandate exists, host unprovable
    return 0                                        # truly unconfigured -> fail-open
}
