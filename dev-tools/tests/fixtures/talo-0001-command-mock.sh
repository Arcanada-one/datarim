#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename "$0")
printf '%s\n' "$command_name $*" >>"${TALO_MOCK_LOG:?}"
case "$command_name" in
    gh)
        case "${TALO_MOCK_GH_MODE:-api-failure}" in
            api-failure) exit 1 ;;
            wrong-blob)
                printf '%040d\n' 0
                exit 0
                ;;
        esac
        case "$*" in
            *"contents/.github/workflows/talo-0001-trusted-replay.yml?ref=main"*)
                printf '%s\n' "${TALO_MOCK_BLOB:?}"
                ;;
            *"contents/dev-tools/provision-talo-0001-trusted-runner.sh?ref=main"*)
                printf '%s\n' "${TALO_MOCK_PROVISIONER_BLOB:?}"
                ;;
            *"contents/dev-tools/systemd/talo-0001-trusted-runner.service?ref=main"*)
                printf '%s\n' "${TALO_MOCK_UNIT_BLOB:?}"
                ;;
            *"runner-groups?per_page=100"*) printf '%s\n' 42 ;;
            *"runner-groups/42/repositories"*)
                printf '%s\n' '{"total_count":1,"repositories":[{"id":1207050134}]}'
                ;;
            *"runner-groups/42/runners"*)
                runner='{"id":7001,"name":"talo-0001-trusted-arcana-devs","os":"Linux","status":"offline","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"talo-0001-trusted"}]}'
                runner_calls=$(grep -c 'runner-groups/42/runners' "${TALO_MOCK_LOG:?}" || true)
                case "${TALO_MOCK_RUNNERS_MODE:-one}" in
                    extra)
                        runner="${runner/\"status\":\"offline\"/\"status\":\"online\"}"
                        printf '{"total_count":2,"runners":[%s,%s]}\n' \
                            "$runner" \
                            '{"id":7002,"name":"other-runner","os":"Linux","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"talo-0001-trusted"}]}'
                        ;;
                    busy)
                        if [ "$runner_calls" -gt 1 ]; then
                            runner="${runner/\"status\":\"offline\",\"busy\":false/\"status\":\"online\",\"busy\":true}"
                        fi
                        printf '{"total_count":1,"runners":[%s]}\n' "$runner"
                        ;;
                    *)
                        if [ "$runner_calls" -gt 1 ]; then
                            runner="${runner/\"status\":\"offline\"/\"status\":\"online\"}"
                        fi
                        printf '{"total_count":1,"runners":[%s]}\n' "$runner"
                        ;;
                esac
                ;;
            *"runner-groups/42"*)
                printf '%s\n' '{"id":42,"name":"talo-0001-trusted","visibility":"selected","default":false,"allows_public_repositories":true,"restricted_to_workflows":true,"selected_workflows":["Arcanada-one/datarim/.github/workflows/talo-0001-trusted-replay.yml@refs/heads/main"]}'
                ;;
            *"registration-token"*) printf '%s\n' fixture-token ;;
            *) exit 1 ;;
        esac
        ;;
    systemctl)
        if [ "${1:-}" = show ]; then
            printf '%s\n' loaded
            exit 0
        fi
        if [ "${1:-}" = stop ] && [ "${TALO_MOCK_STOP_FAILURE:-0}" = 1 ]; then
            exit 1
        fi
        exit 0
        ;;
    sudo)
        while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done
        [ "$#" -gt 0 ] && shift
        "$@"
        ;;
    *) exit 0 ;;
esac
