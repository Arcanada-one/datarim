#!/usr/bin/env bash
# cli/subcommands/run.sh — datarim run <slash-cmd> [args].
# Source: TUNE-0271 plan § Implementation Steps Batch 3.

set -u

run_subcommand() {
    local slash="${1:-}"; shift || true
    if [ -z "$slash" ]; then
        printf '[run] usage: datarim run <slash-cmd> [args]\n' >&2
        return 2
    fi

    local CLI_DIR LIB_DIR
    CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    LIB_DIR="$CLI_DIR/lib"
    # shellcheck source=cli/lib/http.sh
    . "$LIB_DIR/http.sh"
    # shellcheck source=cli/lib/audit.sh
    . "$LIB_DIR/audit.sh"

    local args_json='{}'
    if [ $# -gt 0 ]; then
        args_json=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$@")
    fi

    local class start_ms end_ms duration_ms outcome exit_code body reversibility
    class="$(classify_slash "$slash")"
    start_ms=$(python3 -c "import time;print(int(time.time()*1000))")

    case "$class" in
        sync)
            reversibility="reversible"
            if body=$(http_dispatch_sync "$slash" "$args_json"); then
                exit_code=0; outcome="success"
                printf '%s\n' "$body"
            else
                exit_code=$?; outcome="error"
            fi
            ;;
        forbidden_sync|async)
            reversibility="irreversible"
            if body=$(http_dispatch_async "$slash" "$args_json"); then
                exit_code=0; outcome="success"
                printf '%s\n' "$body"
            else
                exit_code=$?; outcome="error"
            fi
            ;;
        *)
            printf '[run] unknown classification: %s\n' "$class" >&2
            exit_code=1; outcome="error"; reversibility="reversible"
            ;;
    esac

    end_ms=$(python3 -c "import time;print(int(time.time()*1000))")
    duration_ms=$((end_ms - start_ms))
    local hash
    hash="$(audit_args_hash "$slash" "$@")"
    audit_append "run" "$hash" "$reversibility" "$outcome" "$duration_ms" "$exit_code" || true

    return "$exit_code"
}
