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

parse_yaml_inline_list() {
    # Parse "- key: [a, b, c]" inline-array form. Used for file_inventory
    # categories where lists are emitted on a single line.
    local file="$1"
    local key="$2"
    if [ ! -f "$file" ]; then
        return 1
    fi
    awk -v key="$key" '
        $0 ~ "^[[:space:]]+" key ":[[:space:]]*\\[" {
            line = $0
            sub("^[[:space:]]+" key ":[[:space:]]*\\[", "", line)
            sub("\\][[:space:]]*$", "", line)
            n = split(line, parts, /,[[:space:]]*/)
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                if (parts[i] != "") print parts[i]
            }
            exit
        }
    ' "$file"
}

# --- enabled-plugins.md manipulation -----------------------------------------
#
# Each manifest entry is an unindented block opening with "- id: <id>" and
# extending until the next "- id:" or end-of-file. Helpers below treat the
# manifest as a sequence of such blocks.

manifest_has_entry() {
    local manifest="$1" id="$2"
    [ -f "$manifest" ] || return 1
    grep -q "^- id: ${id}$" "$manifest"
}

manifest_field() {
    # Echo scalar field of <id>'s entry. Empty output if absent.
    local manifest="$1" id="$2" field="$3"
    [ -f "$manifest" ] || return 1
    awk -v id="$id" -v field="$field" '
        BEGIN { in_block = 0 }
        /^- id: / {
            in_block = ($0 == "- id: " id) ? 1 : 0
            next
        }
        in_block {
            if (match($0, "^[[:space:]]+" field ":")) {
                line = $0
                sub("^[[:space:]]+" field ":[[:space:]]*", "", line)
                print line
                exit
            }
        }
    ' "$manifest"
}

manifest_remove_entry() {
    local manifest="$1" id="$2"
    [ -f "$manifest" ] || return 1
    local tmp
    tmp="$(mktemp)"
    awk -v id="$id" '
        /^- id: / {
            if ($0 == "- id: " id) { skipping = 1; next }
            skipping = 0
        }
        !skipping
    ' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
}

manifest_dependents_of() {
    # Echo each plugin id that lists <target> in its depends_on list.
    local manifest="$1" target="$2"
    [ -f "$manifest" ] || return 1
    awk -v target="$target" '
        BEGIN { current = ""; in_dep = 0 }
        /^- id: / {
            current = $0
            sub(/^- id: /, "", current)
            in_dep = 0
            next
        }
        /^[[:space:]]+depends_on:[[:space:]]*$/ {
            in_dep = 1
            next
        }
        in_dep && /^[[:space:]]+-[[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]+-[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == target) print current
            next
        }
        in_dep && /^[[:space:]]+[a-z_]+:/ { in_dep = 0 }
        in_dep && /^- / { in_dep = 0 }
    ' "$manifest"
}

# --- locking (mkdir-based, POSIX-portable) ----------------------------------
#
# macOS does not ship `flock`. Use mkdir which is atomic on POSIX filesystems.

acquire_plugin_lock() {
    local lock_dir="$1"
    local timeout="${2:-60}"
    local elapsed=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        if [ "$elapsed" -ge "$timeout" ]; then
            return 3
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 0
}

release_plugin_lock() {
    local lock_dir="$1"
    rmdir "$lock_dir" 2>/dev/null || true
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

# --- snapshot / rollback (TUNE-0101 Phase C) --------------------------------
#
# Snapshots are gzipped tar archives of the runtime root + manifest, taken
# before mutating operations (enable/disable). On failure mid-apply, the
# snapshot is restored verbatim. Stored under
# <ws>/datarim/plugin-storage/.snapshots/<UTC-timestamp>.tar.gz.
#
# Rotation: FIFO cap at DR_PLUGIN_SNAPSHOT_MAX (default 50). Age-based purge
# (>30d) is delegated to `dr-plugin doctor` (Phase D).

DR_PLUGIN_SNAPSHOT_MAX="${DR_PLUGIN_SNAPSHOT_MAX:-50}"

snapshot_dir() {
    local ws="$1"
    echo "$ws/datarim/plugin-storage/.snapshots"
}

snapshot_create() {
    # Args: <workspace> <runtime_root> <manifest_path>
    # Echoes snapshot path on stdout; non-zero on tar failure.
    local ws="$1" runtime="$2" manifest="$3"
    local snap_d
    snap_d="$(snapshot_dir "$ws")"
    mkdir -p "$snap_d" || return 2

    local ts
    ts="$(date -u +"%Y%m%dT%H%M%SZ")"
    local snap="$snap_d/${ts}.tar.gz"

    # Stage runtime tree + manifest, then archive. Staging avoids portability
    # issues with multi -C tar invocations on BSD/macOS tar.
    local stage
    stage="$(mktemp -d "${TMPDIR:-/tmp}/dr-plugin-snap.XXXXXX")" || return 2
    if [ -d "$runtime" ]; then
        # Preserve symlinks (-RP). Empty runtime → cp -R prints nothing harmful.
        cp -RP "$runtime/." "$stage/runtime/" 2>/dev/null || mkdir -p "$stage/runtime"
    else
        mkdir -p "$stage/runtime"
    fi
    if [ -f "$manifest" ]; then
        cp "$manifest" "$stage/manifest.md" || true
    fi
    if ! tar -czf "$snap" -C "$stage" . 2>/dev/null; then
        rm -rf "$stage"
        return 2
    fi
    rm -rf "$stage"
    snapshot_rotate "$snap_d"
    echo "$snap"
}

snapshot_rotate() {
    local snap_d="$1"
    [ -d "$snap_d" ] || return 0
    local count
    count="$(find "$snap_d" -maxdepth 1 -name '*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')"
    [ "$count" -le "$DR_PLUGIN_SNAPSHOT_MAX" ] && return 0
    local excess=$((count - DR_PLUGIN_SNAPSHOT_MAX))
    # Sort by mtime ascending (oldest first) — portable across BSD/GNU.
    # shellcheck disable=SC2038  # snapshot names are UTC timestamps, no spaces.
    find "$snap_d" -maxdepth 1 -name '*.tar.gz' -type f 2>/dev/null \
        | xargs -I{} stat -f "%m %N" {} 2>/dev/null \
        | sort -n \
        | head -n "$excess" \
        | awk '{ $1=""; sub(/^ /,""); print }' \
        | while IFS= read -r f; do
            [ -n "$f" ] && rm -f "$f"
        done
    # GNU stat fallback if BSD `stat -f` failed silently above.
    count="$(find "$snap_d" -maxdepth 1 -name '*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count" -gt "$DR_PLUGIN_SNAPSHOT_MAX" ]; then
        excess=$((count - DR_PLUGIN_SNAPSHOT_MAX))
        find "$snap_d" -maxdepth 1 -name '*.tar.gz' -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -n \
            | head -n "$excess" \
            | awk '{ $1=""; sub(/^ /,""); print }' \
            | while IFS= read -r f; do
                [ -n "$f" ] && rm -f "$f"
            done
    fi
    return 0
}

restore_from_snapshot() {
    # Args: <snapshot_path> <runtime_root> <manifest_path>
    # Wipes managed runtime category subtrees and replaces from snapshot.
    local snap="$1" runtime="$2" manifest="$3"
    [ -f "$snap" ] || { echo "snapshot_restore: snapshot missing: $snap" >&2; return 2; }

    local stage_r
    stage_r="$(mktemp -d "${TMPDIR:-/tmp}/dr-plugin-rst.XXXXXX")" || return 2
    if ! tar -xzf "$snap" -C "$stage_r" 2>/dev/null; then
        rm -rf "$stage_r"
        return 2
    fi

    local cat
    for cat in skills agents commands templates; do
        rm -rf "${runtime:?runtime root must be set}/$cat"
    done
    mkdir -p "$runtime"

    if [ -d "$stage_r/runtime" ]; then
        cp -RP "$stage_r/runtime/." "$runtime/" 2>/dev/null || true
    fi

    if [ -f "$stage_r/manifest.md" ]; then
        cp "$stage_r/manifest.md" "$manifest"
    fi

    rm -rf "$stage_r"
    return 0
}

manifest_active_ids() {
    local manifest="$1"
    [ -f "$manifest" ] || return 0
    awk '/^- id: / { print $3 }' "$manifest"
}

manifest_inventory_of() {
    # Args: <manifest> <id> <category>
    # Echoes whitespace-separated basenames from file_inventory.<cat>.
    local manifest="$1" id="$2" cat="$3"
    [ -f "$manifest" ] || return 0
    awk -v id="$id" -v cat="$cat" '
        BEGIN { in_block=0; in_inv=0 }
        /^- id: / {
            in_block = ($0 == "- id: " id) ? 1 : 0
            in_inv = 0
            next
        }
        in_block && /^[[:space:]]+file_inventory:[[:space:]]*$/ { in_inv=1; next }
        in_inv && $0 ~ "^[[:space:]]+" cat ":[[:space:]]*\\[" {
            line = $0
            sub("^[[:space:]]+" cat ":[[:space:]]*\\[", "", line)
            sub("\\][[:space:]]*$", "", line)
            n = split(line, parts, /,[[:space:]]*/)
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                if (parts[i] != "") print parts[i]
            }
        }
        in_inv && /^[[:space:]]+[a-z_]+:/ && $0 !~ "^[[:space:]]+(skills|agents|commands|templates):" {
            in_inv = 0
        }
    ' "$manifest"
}
