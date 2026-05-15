#!/usr/bin/env bash
#
# check-security-policy.sh — Arcanada Ecosystem Security Policy gate.
#
# Two orthogonal modes:
#   --check                    Presence-gate: SECURITY.md at repo root.
#   --validate-yaml <FILE>     Schema v1 validation of accepted-risk.yml.
#
# Contract source: consumer ecosystem CLAUDE.md
# § Arcanada Ecosystem Security Policy Mandate.
#
# Exit codes:
#   0  pass
#   1  validation / presence failure
#   2  usage error
#   3  validate-yaml: file not found
#
# No external dependencies — pure bash + awk + date. Works on macOS BSD date
# (-j -f) and GNU date (-d) via probe-and-fallback.

set -uo pipefail

SCRIPT_NAME="check-security-policy.sh"
VERSION="1.0.0"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME --check [--repo PATH]
  $SCRIPT_NAME --validate-yaml FILE
  $SCRIPT_NAME --help
  $SCRIPT_NAME --version

Modes:
  --check                    Verify SECURITY.md exists at repo root.
                             Default --repo is "." (current directory).
                             Exit 0 if present, 1 if missing,
                             2 if --repo path is not a directory.

  --validate-yaml FILE       Validate accepted-risk.yml against schema v1.
                             Exit 0 on pass, 1 on validation failure,
                             3 if FILE does not exist.

Schema v1 rules (validate-yaml):
  schema_version: 1
  entries[].id          matches ^(GHSA|RUSTSEC|CVE)-
  entries[].pkg         non-empty string
  entries[].severity    enum {critical, high, medium, low}
  entries[].scope       enum {runtime, devdep, transitive}
  entries[].reason      >= 20 non-whitespace characters
  entries[].last_review ISO date YYYY-MM-DD
  entries[].re_review   ISO date <= last_review + 90 days
  entries[].reviewed_by enum {agent, human}
EOF
}

err() {
    echo "ERROR: $*" >&2
}

# Cross-platform date-to-epoch helper. Returns 0 + epoch on stdout when the
# input matches YYYY-MM-DD, non-zero otherwise.
date_to_epoch() {
    local d="$1"
    [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    if date -j -f "%Y-%m-%d" "$d" "+%s" >/dev/null 2>&1; then
        date -j -f "%Y-%m-%d" "$d" "+%s"
        return 0
    fi
    if date -d "$d" "+%s" >/dev/null 2>&1; then
        date -d "$d" "+%s"
        return 0
    fi
    return 1
}

cmd_check() {
    local repo="."
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo)
                shift
                [ $# -gt 0 ] || { usage >&2; return 2; }
                repo="$1"
                shift
                ;;
            *)
                err "unknown argument for --check: $1"
                usage >&2
                return 2
                ;;
        esac
    done
    if [ ! -d "$repo" ]; then
        err "--repo path is not a directory: $repo"
        return 2
    fi
    if [ -f "$repo/SECURITY.md" ]; then
        echo "OK: $repo/SECURITY.md present"
        return 0
    fi
    echo "MISSING: $repo/SECURITY.md not found"
    return 1
}

# Validate one accepted-risk.yml file. Pure awk pass + a post-walk date check
# in bash. Outputs human-readable findings on stderr; one finding per line.
cmd_validate_yaml() {
    local file="$1"
    if [ ! -f "$file" ]; then
        err "file not found: $file"
        return 3
    fi

    # Pass 1: structural — schema_version, entries[] presence, per-entry
    # required fields with enum / regex / length checks. Emits findings to
    # stderr and a tab-separated `last_review<TAB>re_review` record per entry
    # on stdout (consumed by the date-window check below).
    local awk_out
    awk_out=$(awk -v file="$file" '
        BEGIN {
            schema_seen = 0
            in_entries = 0
            entry_idx = 0
            findings = 0
            sev_re   = "^(critical|high|medium|low)$"
            scope_re = "^(runtime|devdep|transitive)$"
            who_re   = "^(agent|human)$"
            id_re    = "^(GHSA|RUSTSEC|CVE)-"
            date_re  = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
        }
        function strip(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function unquote(s,    t) {
            t = s
            if (t ~ /^".*"$/ || t ~ /^'\''.*'\''$/) {
                t = substr(t, 2, length(t) - 2)
            }
            return t
        }
        function emit(msg) {
            print msg | "cat 1>&2"
            findings++
        }
        function close_entry() {
            if (entry_idx == 0) return
            need = "id pkg severity scope reason last_review re_review reviewed_by"
            n = split(need, want, " ")
            for (i = 1; i <= n; i++) {
                k = want[i]
                if (!(k in cur)) {
                    emit(file ": entry " entry_idx ": missing required field: " k)
                }
            }
            if (("id" in cur) && (cur["id"] !~ id_re)) {
                emit(file ": entry " entry_idx ": id does not match ^(GHSA|RUSTSEC|CVE)-: " cur["id"])
            }
            if (("severity" in cur) && (cur["severity"] !~ sev_re)) {
                emit(file ": entry " entry_idx ": invalid severity: " cur["severity"])
            }
            if (("scope" in cur) && (cur["scope"] !~ scope_re)) {
                emit(file ": entry " entry_idx ": invalid scope: " cur["scope"])
            }
            if (("reviewed_by" in cur) && (cur["reviewed_by"] !~ who_re)) {
                emit(file ": entry " entry_idx ": invalid reviewed_by: " cur["reviewed_by"])
            }
            if ("reason" in cur) {
                r = cur["reason"]
                gsub(/[[:space:]]/, "", r)
                if (length(r) < 20) {
                    emit(file ": entry " entry_idx ": reason must be >= 20 non-whitespace characters")
                }
            }
            if (("last_review" in cur) && (cur["last_review"] !~ date_re)) {
                emit(file ": entry " entry_idx ": last_review is not YYYY-MM-DD: " cur["last_review"])
            }
            if (("re_review" in cur) && (cur["re_review"] !~ date_re)) {
                emit(file ": entry " entry_idx ": re_review is not YYYY-MM-DD: " cur["re_review"])
            }
            if (("last_review" in cur) && ("re_review" in cur) && \
                (cur["last_review"] ~ date_re) && (cur["re_review"] ~ date_re)) {
                print cur["last_review"] "\t" cur["re_review"] "\t" entry_idx
            }
            delete cur
        }
        # --- token recognition -----------------------------------------
        /^[[:space:]]*#/    { next }   # comment
        /^[[:space:]]*$/    { next }   # blank
        /^schema_version:[[:space:]]*1[[:space:]]*$/ {
            schema_seen = 1
            next
        }
        /^schema_version:/  {
            emit(file ": schema_version is not 1: " $0)
            schema_seen = 1
            next
        }
        /^entries:[[:space:]]*$/ {
            in_entries = 1
            next
        }
        /^[[:space:]]*-[[:space:]]+id:/ {
            close_entry()
            entry_idx++
            line = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", line)
            cur["id"] = unquote(strip(line))
            next
        }
        in_entries == 1 && /^[[:space:]]+[a-z_]+:/ {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            k = line
            sub(/:.*$/, "", k)
            v = line
            sub(/^[a-z_]+:[[:space:]]*/, "", v)
            cur[k] = unquote(strip(v))
            next
        }
        END {
            close_entry()
            if (!schema_seen) {
                emit(file ": missing required top-level field: schema_version")
            }
            if (entry_idx == 0) {
                emit(file ": no entries found (schema requires entries[] list)")
            }
            exit (findings > 0 ? 1 : 0)
        }
    ' "$file")
    local awk_status=$?

    # Pass 2: re_review <= last_review + 90 days. We received tab-separated
    # records on stdout from the awk pass.
    local window_status=0
    local SECONDS_PER_DAY=86400
    local LIMIT_DAYS=90
    while IFS=$'\t' read -r last re idx; do
        [ -z "${last:-}" ] && continue
        local last_epoch re_epoch
        last_epoch=$(date_to_epoch "$last") || { window_status=1; continue; }
        re_epoch=$(date_to_epoch "$re") || { window_status=1; continue; }
        local diff_days=$(( (re_epoch - last_epoch) / SECONDS_PER_DAY ))
        if [ "$diff_days" -gt "$LIMIT_DAYS" ]; then
            err "$file: entry $idx: re_review ($re) > last_review + 90d ($last)"
            window_status=1
        fi
        if [ "$diff_days" -lt 0 ]; then
            err "$file: entry $idx: re_review ($re) is before last_review ($last)"
            window_status=1
        fi
    done <<< "$awk_out"

    if [ "$awk_status" -ne 0 ] || [ "$window_status" -ne 0 ]; then
        echo "FAIL: $file"
        return 1
    fi
    echo "OK: $file"
    return 0
}

main() {
    [ $# -gt 0 ] || { usage >&2; exit 2; }
    case "$1" in
        --check)
            shift
            cmd_check "$@"
            ;;
        --validate-yaml)
            shift
            [ $# -gt 0 ] || { usage >&2; exit 2; }
            cmd_validate_yaml "$1"
            ;;
        --help|-h)
            usage
            ;;
        --version)
            echo "$SCRIPT_NAME $VERSION"
            ;;
        *)
            err "unknown subcommand: $1"
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
