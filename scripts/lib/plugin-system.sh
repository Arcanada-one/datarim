# shellcheck shell=bash
# plugin-system.sh — shared helpers for /dr-plugin (TUNE-0101).
#
# Public API:
#   validate_plugin_id <id>           — kebab-case, [a-z][a-z0-9-]{0,31}
#   validate_source <source>          — builtin|abs-path|https-git-URL; rejects
#                                       path traversal and embedded credentials
#   parse_plugin_yaml <file> <field>  — extract scalar field via awk; rejects
#                                       CRLF and missing files
#   parse_yaml_list <file> <key>      — extract list items under <key>: into
#                                       newline-separated stdout
#
# Style: POSIX-friendly bash, no external dependencies beyond awk and grep.
# Bash 3.2 compatible (macOS default) — no associative arrays, no readarray.
#
# Source: PRD-TUNE-0101, plans/TUNE-0101-plan.md § Phase A.

# --- ID validation -----------------------------------------------------------

validate_plugin_id() {
    local id="$1"
    if [ -z "$id" ]; then
        echo "validate_plugin_id: empty id" >&2
        return 1
    fi
    if [ "${#id}" -gt 32 ]; then
        echo "validate_plugin_id: id exceeds 32 chars: $id" >&2
        return 1
    fi
    # LC_ALL=C forces byte-level (not locale-aware) matching for [a-z].
    # Without it, on macOS bash with UTF-8 collation, [a-z] also matches A-Z.
    local LC_ALL=C
    case "$id" in
        [a-z]*) : ;;
        *)
            echo "validate_plugin_id: must start with [a-z]: $id" >&2
            return 1
            ;;
    esac
    case "$id" in
        *[!a-z0-9-]*)
            echo "validate_plugin_id: contains invalid chars (allowed: a-z 0-9 -): $id" >&2
            return 1
            ;;
    esac
    return 0
}

# --- source validation -------------------------------------------------------

validate_source() {
    local src="$1"
    if [ -z "$src" ]; then
        echo "validate_source: empty source" >&2
        return 1
    fi

    # Builtin keyword for datarim-core.
    if [ "$src" = "builtin" ]; then
        return 0
    fi

    # Reject path traversal anywhere in the string.
    case "$src" in
        *..* )
            echo "validate_source: path traversal not allowed: $src" >&2
            return 1
            ;;
    esac

    # Git URL form.
    case "$src" in
        https://*|http://*)
            # Reject embedded credentials (user:token@host).
            case "$src" in
                *@*)
                    # Allow ssh-like git@github.com form? No — we accept only
                    # https for now (plain hostnames don't contain @).
                    echo "validate_source: embedded credentials/token not allowed in URL: $src" >&2
                    return 1
                    ;;
            esac
            return 0
            ;;
    esac

    # Absolute path form.
    case "$src" in
        /*)
            return 0
            ;;
    esac

    echo "validate_source: must be 'builtin', absolute path, or https URL: $src" >&2
    return 1
}

# --- YAML parsing (awk-based, no eval) --------------------------------------

_check_no_crlf() {
    local file="$1"
    if grep -q $'\r' "$file" 2>/dev/null; then
        echo "parse_plugin_yaml: CRLF line endings rejected (security): $file" >&2
        return 1
    fi
    return 0
}

parse_plugin_yaml() {
    local file="$1"
    local field="$2"
    if [ ! -f "$file" ]; then
        echo "parse_plugin_yaml: file not found: $file" >&2
        return 1
    fi
    _check_no_crlf "$file" || return 1

    # Extract top-level scalar field "field: value".
    # Strips inline comments and surrounding whitespace.
    awk -v key="$field" '
        # Skip comments and blank lines.
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        # Match top-level (no leading space) "key: value".
        $0 ~ "^"key"[[:space:]]*:" {
            sub("^"key"[[:space:]]*:[[:space:]]*", "")
            sub("[[:space:]]*#.*$", "")     # trim trailing comment
            sub("[[:space:]]+$", "")        # trim trailing whitespace
            # Strip surrounding quotes if present.
            gsub("^[\"\x27]|[\"\x27]$", "")
            print
            exit
        }
    ' "$file"
}

parse_yaml_list() {
    local file="$1"
    local key="$2"
    if [ ! -f "$file" ]; then
        echo "parse_yaml_list: file not found: $file" >&2
        return 1
    fi
    _check_no_crlf "$file" || return 1

    # State machine: enter "list mode" after "key:" line, exit when we see a
    # non-indented non-list line. Capture lines starting with "- ".
    awk -v key="$key" '
        BEGIN { in_list = 0 }
        /^[[:space:]]*#/ { next }
        # Top-level "key:" with no value on the same line opens list scope.
        $0 ~ "^"key"[[:space:]]*:[[:space:]]*$" {
            in_list = 1
            next
        }
        # Top-level "key:" with inline value (e.g. flow style not supported here).
        $0 ~ "^"key"[[:space:]]*:" {
            in_list = 0
            next
        }
        in_list == 1 {
            # End of list: encountered another top-level key (no leading space,
            # ends with colon).
            if ($0 ~ /^[A-Za-z_]/) {
                in_list = 0
                next
            }
            # List item: "  - value" or "- value".
            if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
                line = $0
                sub("^[[:space:]]*-[[:space:]]+", "", line)
                sub("[[:space:]]*#.*$", "", line)
                sub("[[:space:]]+$", "", line)
                gsub("^[\"\x27]|[\"\x27]$", "", line)
                print line
            }
        }
    ' "$file"
}
