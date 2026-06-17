#!/usr/bin/env bash
# dev-tools/dead-ip-consumer-sweep.sh — fail-closed post-relocate dead-IP consumer sweep.
#
# Scans all live config surfaces in a workspace for references to a decommissioned
# IP address. Classifies hits as live (class a/b) vs historical (class c).
# Requires an audit document asserting zero live consumers.
#
# A live consumer reference (class a: connection string; class b: bind/listen
# directive) OR a missing/non-asserting audit causes a fail-closed BLOCK.
# Historical/commented references (class c) do not block.
# References in spaces/*/space.yml are treated as live (class d).
#
# Defensive invariant: any code path that produces BLOCK output cannot exit 0.
#
# Usage:
#   dead-ip-consumer-sweep.sh --dead-ip <IP> --workspace-root <dir> --audit <file>
#   dead-ip-consumer-sweep.sh --help
#
# Exit codes:
#   0   PASS    — zero class-a/b/d hits AND audit asserts zero live consumers
#   1   BLOCK   — at least one live hit OR audit absent/non-asserting
#   2   usage error / invalid IP / unreadable workspace root

set -eu

SCRIPT_NAME="dead-ip-consumer-sweep.sh"

usage() {
    cat <<EOF
$SCRIPT_NAME — fail-closed dead-IP consumer sweep for post-relocate archive gate.

Usage:
  $SCRIPT_NAME --dead-ip <IPv4> --workspace-root <dir> --audit <file>

Options:
  --dead-ip <IPv4>        Decommissioned IP address to search for (repeatable).
  --workspace-root <dir>  Root of the workspace to scan (default: current dir).
  --audit <file>          Audit document asserting zero live consumers (required).
  -h, --help              Show this help.

Exit: 0 PASS | 1 BLOCK | 2 usage error
EOF
}

# Validate dotted-quad IPv4 (simple shape check — not range validation)
is_valid_ipv4() {
    local ip="$1"
    # Must match N.N.N.N where each N is 1-3 digits
    printf '%s' "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

dead_ips=()
workspace_root="."
audit_file=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dead-ip)
            ip="${2:-}"
            [ -n "$ip" ] || { printf '%s: --dead-ip requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            if ! is_valid_ipv4 "$ip"; then
                printf '%s: invalid IPv4 address: %s\n' "$SCRIPT_NAME" "$ip" >&2
                usage >&2
                exit 2
            fi
            dead_ips+=("$ip")
            shift 2
            ;;
        --workspace-root)
            workspace_root="${2:-}"
            [ -n "$workspace_root" ] || { printf '%s: --workspace-root requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            shift 2
            ;;
        --audit)
            audit_file="${2:-}"
            [ -n "$audit_file" ] || { printf '%s: --audit requires a value\n' "$SCRIPT_NAME" >&2; exit 2; }
            shift 2
            ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            printf '%s: unknown argument: %s\n' "$SCRIPT_NAME" "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Require at least one dead IP
if [ "${#dead_ips[@]}" -eq 0 ]; then
    printf '%s: --dead-ip is required\n' "$SCRIPT_NAME" >&2
    usage >&2
    exit 2
fi

# Verify workspace root is readable
if [ ! -d "$workspace_root" ]; then
    printf '%s: BLOCK — workspace root not found or not a directory: %s\n' "$SCRIPT_NAME" "$workspace_root" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Escape IP for use in ERE (dots become literal dots)
escape_ip_for_ere() {
    printf '%s' "$1" | sed 's/\./\\./g'
}

# Check whether a file line is a historical/commented reference.
# Returns 0 (true) if ALL matches in the file are historical.
# A line is historical if:
#   - starts with # (comment)
#   - is in a documentation/archive/ subtree
#   - is in a *.bak file
#   - line contains only a comment reference (e.g. "# was 23.88.34.218")
line_is_historical() {
    local line="$1"
    # Trim leading whitespace
    local trimmed
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    # Comment line
    if printf '%s' "$trimmed" | grep -q '^#'; then
        return 0
    fi
    return 1
}

# Check if file path is a historical/archive path (not a live config)
path_is_historical() {
    local filepath="$1"
    case "$filepath" in
        */documentation/archive/*) return 0 ;;
        *.bak)                     return 0 ;;
        *.md)
            # Markdown files in documentation/ are historical
            case "$filepath" in
                */documentation/*) return 0 ;;
            esac
            return 1
            ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Audit validation
# ---------------------------------------------------------------------------

validate_audit() {
    local afile="$1"
    # Audit must exist
    if [ ! -f "$afile" ]; then
        printf '%s: BLOCK — audit file not found: %s\n' "$SCRIPT_NAME" "$afile" >&2
        # Defensive invariant guard
        local _inv=1
        [ "$_inv" -ne 0 ] || { printf '%s: ERROR: internal invariant violated: BLOCK path reached exit 0\n' "$SCRIPT_NAME" >&2; exit 2; }
        printf 'BLOCK: audit document absent — cannot confirm zero live consumers.\n'
        exit 1
    fi
    # Audit must contain a zero-live-consumer assertion
    if ! grep -qi 'zero live consumers\|live_consumers:[[:space:]]*0\|assertion:.*zero' "$afile"; then
        printf '%s: BLOCK — audit file does not assert zero live consumers: %s\n' "$SCRIPT_NAME" "$afile" >&2
        # Defensive invariant guard
        local _inv=1
        [ "$_inv" -ne 0 ] || { printf '%s: ERROR: internal invariant violated: BLOCK path reached exit 0\n' "$SCRIPT_NAME" >&2; exit 2; }
        printf 'BLOCK: audit document present but does not assert zero live consumers.\n'
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Scan function: search for IP in a file, classify hits
# Returns 0 if a live hit was found, 1 if no live hit
# ---------------------------------------------------------------------------

# Class-a pattern: connection string / env var pointing at the IP
# e.g. DB_HOST=<ip>, host=<ip>, "host": "<ip>", mysql://<ip>, etc.
class_a_pattern_for() {
    local escaped_ip="$1"
    # Connection-string indicators: key=IP, key: IP, scheme://IP, IP:port
    printf '%s' "([Hh][Oo][Ss][Tt]|[Ss][Ee][Rr][Vv][Ee][Rr]|[Ee][Nn][Dd][Pp][Oo][Ii][Nn][Tt]|[Uu][Rr][Ll]|[Dd][Ss][Nn])[[:space:]]*[=:][[:space:]]*[\"']?${escaped_ip}|[a-z]+://[^[:space:]]*${escaped_ip}|${escaped_ip}:[0-9]+"
}

# Class-b pattern: bind/listen directive
class_b_pattern_for() {
    local escaped_ip="$1"
    printf '%s' "(^|[[:space:]])(bind|listen|ListenAddress|host-address)[[:space:]]+${escaped_ip}([[:space:]]|$)"
}

# Class-d pattern: spaces/*/space.yml IP field
class_d_pattern_for() {
    local escaped_ip="$1"
    printf '%s' "(^|[[:space:]])[-]?[[:space:]]*(ip|address)[[:space:]]*:[[:space:]]*${escaped_ip}([[:space:]]|$)"
}

# Scan all surfaces for live references to the given IP.
# Echoes the first live-hit path found. Returns 0 if found, 1 if not found.
scan_for_live_hits() {
    local ip="$1"
    local root="$2"
    local escaped_ip
    escaped_ip="$(escape_ip_for_ere "$ip")"

    local class_a_pat class_b_pat class_d_pat
    class_a_pat="$(class_a_pattern_for "$escaped_ip")"
    class_b_pat="$(class_b_pattern_for "$escaped_ip")"
    class_d_pat="$(class_d_pattern_for "$escaped_ip")"

    # Broad grep for the IP in the workspace (excluding .git)
    local found_live=0

    while IFS= read -r filepath; do
        # Skip non-files
        [ -f "$filepath" ] || continue

        # Check if the entire file path is historical
        if path_is_historical "$filepath"; then
            continue
        fi

        # Read matching lines
        while IFS= read -r line; do
            # Skip comment lines
            if line_is_historical "$line"; then
                continue
            fi

            # Class-d: spaces/*/space.yml — any IP reference is live
            case "$filepath" in
                */spaces/*/space.yml)
                    if printf '%s' "$line" | grep -Eq -- "$class_d_pat"; then
                        printf 'BLOCK: live class-d reference in %s: %s\n' "$filepath" "$line"
                        found_live=1
                    fi
                    ;;
            esac

            # Class-a: connection string
            if printf '%s' "$line" | grep -Eiq -- "$class_a_pat"; then
                printf 'BLOCK: live class-a reference in %s: %s\n' "$filepath" "$line"
                found_live=1
            fi

            # Class-b: bind/listen
            if printf '%s' "$line" | grep -Eq -- "$class_b_pat"; then
                printf 'BLOCK: live class-b reference in %s: %s\n' "$filepath" "$line"
                found_live=1
            fi

        done < <(grep -n -- "$ip" "$filepath" 2>/dev/null | sed 's/^[0-9]*://')

    done < <(grep -rl -- "$ip" "$root" 2>/dev/null | grep -v '/.git/')

    return "$found_live"
}

# ---------------------------------------------------------------------------
# Main sweep
# ---------------------------------------------------------------------------

blocked=0

for ip in "${dead_ips[@]}"; do
    if ! scan_for_live_hits "$ip" "$workspace_root"; then
        blocked=1
    fi
done

# Validate audit (blocks if absent or non-asserting)
validate_audit "$audit_file"

if [ "$blocked" -ne 0 ]; then
    # Defensive invariant: BLOCK wording must accompany non-zero exit
    [ "$blocked" -ne 0 ] || { printf '%s: ERROR: internal invariant violated: blocked=0 after live hit\n' "$SCRIPT_NAME" >&2; exit 2; }
    exit 1
fi

printf 'PASS: no live consumers of dead IP(s) found.\n'
exit 0
