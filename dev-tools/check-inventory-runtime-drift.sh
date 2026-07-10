#!/usr/bin/env bash
# dev-tools/check-inventory-runtime-drift.sh — declarative-inventory vs runtime drift auditor (TUNE-0124).
#
# Weekly cross-check of a declarative host inventory (public IP, Tailscale IP,
# firewall posture per host) against the live runtime facts probed over SSH.
# Catches silent documentation drift such as a public-IP swap that never made
# it back into the inventory file and lay dormant for months.
#
# Generalized framework tool: it hardcodes NO hosts, IPs, SSH users, or file
# paths. The inventory path, the per-host SSH targets, and (for testing) the
# probe transport are all supplied as arguments. The ecosystem invokes it with
# its own inventory file, e.g.:
#   check-inventory-runtime-drift.sh --inventory <path/to/Servers.md>
#
# Inventory format (host-fact block, one block per host, order-independent):
#   host: <ssh-target>            # SSH destination (user@host or ssh_config alias)
#   public_ip: <IPv4>             # declared public IPv4        (optional field)
#   tailscale_ip: <IPv4>          # declared Tailscale/mesh IPv4 (optional field)
#   firewall: <active|inactive>   # declared firewall posture   (optional field)
# Blocks are separated by a line whose only non-whitespace content is one or
# more hyphens, or by a fresh `host:` key. Lines outside any recognised key are
# ignored, so the block may live inside a wider Markdown table/prose file.
#
# Runtime probe (default transport: ssh) gathers, per host:
#   public_ip     — curl -fsS ifconfig.me   (or an equivalent echo service)
#   tailscale_ip  — tailscale status --json | first Self.TailscaleIPs entry
#   firewall      — ufw status | "active"/"inactive"  (falls back to iptables)
# The transport is injectable via --probe-cmd for offline/test runs; the probe
# command receives the ssh target as $1 and the fact name as $2 and must print
# the runtime value on stdout (empty = unreachable/unknown).
#
# Exit codes:
#   0   OK      — every declared fact matches its runtime counterpart
#   1   DRIFT   — at least one declared fact differs from runtime
#   2   usage error / unreadable inventory
#
# On drift the tool prints one machine-readable line per divergence:
#   DRIFT <host> <fact> declared=<value> runtime=<value>
# which a caller (e.g. an ops notifier) can forward as a warning event.

set -uo pipefail

SCRIPT_NAME="check-inventory-runtime-drift.sh"
VERSION="1.0.0"

usage() {
    cat <<EOF
$SCRIPT_NAME — declarative-inventory vs runtime drift auditor.

Usage:
  $SCRIPT_NAME --inventory <file> [--probe-cmd <cmd>] [--host <ssh-target>]...
               [--quiet] [--format text|json]

Options:
  --inventory <file>   Declarative inventory file to audit (required).
  --probe-cmd <cmd>    Runtime probe transport. Invoked as: <cmd> <host> <fact>
                       where <fact> is public_ip|tailscale_ip|firewall. Must
                       print the runtime value on stdout. Default: built-in ssh
                       probe. Override for offline testing.
  --host <ssh-target>  Restrict the audit to this host (repeatable). Default:
                       every host block found in the inventory.
  --quiet              Suppress the per-fact OK lines; still print DRIFT lines.
  --format FMT         text (default) | json (one JSON object per line).
  --version            Print version and exit.
  -h, --help           Show this help.

Exit: 0 OK (no drift) | 1 DRIFT found | 2 usage / IO error
EOF
}

# ---------------------------------------------------------------------------
# Built-in SSH runtime probe. Prints the runtime value for one fact, or empty
# on failure/unreachable. Kept side-effect-free and read-only on the target.
# ---------------------------------------------------------------------------
default_probe() {
    local host="$1" fact="$2"
    case "$fact" in
        public_ip)
            ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
                'curl -fsS --max-time 10 ifconfig.me' 2>/dev/null | tr -d '[:space:]'
            ;;
        tailscale_ip)
            ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
                'tailscale status --json' 2>/dev/null \
                | grep -oE '"TailscaleIPs":\[[^]]*' \
                | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
                | head -n1
            ;;
        firewall)
            local out
            out=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
                'command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null || iptables -S 2>/dev/null' \
                2>/dev/null)
            if printf '%s' "$out" | grep -qiE 'Status: active|-A '; then
                printf 'active'
            elif [ -n "$out" ]; then
                printf 'inactive'
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
inventory=""
probe_cmd=""
quiet=0
format="text"
declare -a only_hosts=()

while [ $# -gt 0 ]; do
    case "$1" in
        --inventory)
            [ $# -ge 2 ] || { printf '%s: --inventory requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            inventory="$2"; shift 2 ;;
        --probe-cmd)
            [ $# -ge 2 ] || { printf '%s: --probe-cmd requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            probe_cmd="$2"; shift 2 ;;
        --host)
            [ $# -ge 2 ] || { printf '%s: --host requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            only_hosts+=("$2"); shift 2 ;;
        --quiet)
            quiet=1; shift ;;
        --format)
            [ $# -ge 2 ] || { printf '%s: --format requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            format="$2"; shift 2 ;;
        --version)
            printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"; exit 0 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            printf '%s: unknown argument: %s\n' "$SCRIPT_NAME" "$1" >&2
            usage >&2
            exit 2 ;;
    esac
done

[ -n "$inventory" ] || { printf '%s: --inventory is required\n' "$SCRIPT_NAME" >&2; usage >&2; exit 2; }
[ -r "$inventory" ] || { printf '%s: inventory not readable: %s\n' "$SCRIPT_NAME" "$inventory" >&2; exit 2; }
case "$format" in
    text|json) ;;
    *) printf '%s: invalid --format: %s\n' "$SCRIPT_NAME" "$format" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Probe dispatch: honour --probe-cmd if given, else the built-in ssh probe.
# ---------------------------------------------------------------------------
probe() {
    local host="$1" fact="$2"
    if [ -n "$probe_cmd" ]; then
        # shellcheck disable=SC2086
        $probe_cmd "$host" "$fact"
    else
        default_probe "$host" "$fact"
    fi
}

# ---------------------------------------------------------------------------
# host_in_scope <host> — honour --host allowlist (empty allowlist = all).
# ---------------------------------------------------------------------------
host_in_scope() {
    local h="$1"
    [ "${#only_hosts[@]}" -eq 0 ] && return 0
    local x
    for x in "${only_hosts[@]}"; do
        [ "$x" = "$h" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# emit — one result line, in the chosen format.
#   status: OK|DRIFT   host fact declared runtime
# ---------------------------------------------------------------------------
emit() {
    local status="$1" host="$2" fact="$3" declared="$4" runtime="$5"
    if [ "$format" = json ]; then
        printf '{"status":"%s","host":"%s","fact":"%s","declared":"%s","runtime":"%s"}\n' \
            "$status" "$host" "$fact" "$declared" "$runtime"
    else
        if [ "$status" = DRIFT ]; then
            printf 'DRIFT %s %s declared=%s runtime=%s\n' "$host" "$fact" "$declared" "$runtime"
        else
            printf 'OK %s %s %s\n' "$host" "$fact" "$declared"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Parse the inventory into host blocks and audit each declared fact.
# ---------------------------------------------------------------------------
drift_found=0
cur_host=""
declare -A declared_fact=()

flush_block() {
    [ -n "$cur_host" ] || { declared_fact=(); return 0; }
    if host_in_scope "$cur_host"; then
        local fact declared runtime
        for fact in public_ip tailscale_ip firewall; do
            declared="${declared_fact[$fact]:-}"
            [ -n "$declared" ] || continue
            runtime="$(probe "$cur_host" "$fact")"
            if [ -z "$runtime" ]; then
                # Unreachable / unknown runtime is not counted as drift; note it.
                [ "$quiet" -eq 1 ] || emit OK "$cur_host" "$fact" "$declared" ""
            elif [ "$declared" = "$runtime" ]; then
                [ "$quiet" -eq 1 ] || emit OK "$cur_host" "$fact" "$declared" "$runtime"
            else
                emit DRIFT "$cur_host" "$fact" "$declared" "$runtime"
                drift_found=1
            fi
        done
    fi
    cur_host=""
    declared_fact=()
}

# Read line by line. A block ends at a separator (hyphens-only line) or when a
# new `host:` key starts. Leading/trailing whitespace and Markdown list/table
# decoration ("- ", "| ") on keys are tolerated.
while IFS= read -r line || [ -n "$line" ]; do
    # Strip common Markdown leading decoration for key detection only.
    stripped="${line#"${line%%[![:space:]]*}"}"      # ltrim
    stripped="${stripped#- }"
    stripped="${stripped#| }"

    # Separator line (one or more hyphens, nothing else) closes the block.
    if printf '%s' "$line" | grep -qE '^[[:space:]]*-+[[:space:]]*$'; then
        flush_block
        continue
    fi

    case "$stripped" in
        host:*)
            # New host key starts a new block; flush the previous one first.
            flush_block
            cur_host="$(printf '%s' "${stripped#host:}" | tr -d '[:space:]')"
            ;;
        public_ip:*)
            declared_fact[public_ip]="$(printf '%s' "${stripped#public_ip:}" | tr -d '[:space:]')" ;;
        tailscale_ip:*)
            declared_fact[tailscale_ip]="$(printf '%s' "${stripped#tailscale_ip:}" | tr -d '[:space:]')" ;;
        firewall:*)
            declared_fact[firewall]="$(printf '%s' "${stripped#firewall:}" | tr -d '[:space:]')" ;;
        *)
            : ;;  # ignore unrelated lines (prose, table headers, other keys)
    esac
done < "$inventory"

# Flush the final open block (file that did not end on a separator).
flush_block

exit "$drift_found"
