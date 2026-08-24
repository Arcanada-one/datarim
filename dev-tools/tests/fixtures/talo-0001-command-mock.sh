#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename "$0")
printf '%s\n' "$command_name $*" >>"${TALO_MOCK_LOG:?}"
case "$command_name" in
    gh)
        if [ "${TALO_MOCK_GH_MODE:-api-failure}" = wrong-blob ]; then
            printf '%040d\n' 0
            exit 0
        fi
        exit 1
        ;;
    *) exit 0 ;;
esac
