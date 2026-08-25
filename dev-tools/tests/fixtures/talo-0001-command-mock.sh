#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename "$0")
printf '%s\n' "$command_name $*" >>"${TALO_MOCK_LOG:?}"
case "$command_name" in
    chmod|chown)
        "/usr/bin/$command_name" "$@"
        ;;
    pgrep)
        if [ "${TALO_MOCK_RUNNER_PROCESS:-0}" = late ]; then
            count=$(cat "${TALO_MOCK_PGREP_COUNTER:?}")
            count=$((count + 1))
            printf '%s\n' "$count" >"$TALO_MOCK_PGREP_COUNTER"
            [ "$count" -ge 2 ]
        else
            [ "${TALO_MOCK_RUNNER_PROCESS:-0}" = 1 ]
        fi
        ;;
    getent)
        [ "${1:-}" = passwd ]
        [ "${2:-}" = "${TALO_MOCK_RUNNER_USER:?}" ]
        printf '%s:x:%s:%s:Trusted replay fixture:/srv/talo-0001-trusted:/usr/sbin/nologin\n' \
            "$TALO_MOCK_RUNNER_USER" "${TALO_MOCK_RUNNER_UID:?}" \
            "${TALO_MOCK_RUNNER_GID:?}"
        ;;
    gh)
        case "${TALO_MOCK_GH_MODE:-api-failure}" in
            api-failure) exit 1 ;;
            wrong-blob)
                printf '%040d\n' 0
                exit 0
                ;;
        esac
        if [ "${TALO_MOCK_GROUP_MUTATION_FAILURE:-0}" = 1 ] \
            && [[ " $* " == *" --method PATCH "* ]]; then
            exit 1
        fi
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
                if [ -f "${TALO_MOCK_REGISTRATION_REMOVED:-/nonexistent}" ]; then
                    printf '%s\n' '{"total_count":0,"runners":[]}'
                    exit 0
                fi
                runner='{"id":7001,"name":"talo-0001-trusted-arcana-devs","os":"Linux","status":"offline","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"talo-0001-trusted"}]}'
                runner_calls=$(grep -c 'runner-groups/42/runners' "${TALO_MOCK_LOG:?}" || true)
                case "${TALO_MOCK_RUNNERS_MODE:-one}" in
                    unbound-pre)
                        printf '{"total_count":1,"runners":[%s]}\n' "$runner"
                        ;;
                    remote-before-local)
                        if [ ! -f "${TALO_MOCK_CONFIG_STARTED:?}" ]; then
                            printf '%s\n' '{"total_count":0,"runners":[]}'
                        else
                            printf '{"total_count":1,"runners":[%s]}\n' "$runner"
                        fi
                        ;;
                    fresh-hostile)
                        if [ ! -f "${TALO_MOCK_CONFIG_STARTED:?}" ]; then
                            printf '%s\n' '{"total_count":0,"runners":[]}'
                        else
                            printf '{"total_count":2,"runners":[%s,%s]}\n' \
                                "$runner" \
                                '{"id":7002,"name":"hostile-runner","os":"Linux","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"talo-0001-trusted"}]}'
                        fi
                        ;;
                    fresh-timeout)
                        printf '%s\n' '{"total_count":0,"runners":[]}'
                        ;;
                    fresh)
                        if [ ! -f "${TALO_MOCK_CONFIG_STARTED:?}" ]; then
                            printf '%s\n' '{"total_count":0,"runners":[]}'
                        else
                            [ "$runner_calls" -le 3 ] \
                                || runner="${runner/\"status\":\"offline\"/\"status\":\"online\"}"
                            printf '{"total_count":1,"runners":[%s]}\n' "$runner"
                        fi
                        ;;
                    extra)
                        runner="${runner/\"status\":\"offline\"/\"status\":\"online\"}"
                        printf '{"total_count":2,"runners":[%s,%s]}\n' \
                            "$runner" \
                            '{"id":7002,"name":"other-runner","os":"Linux","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"},{"name":"talo-0001-trusted"}]}'
                        ;;
                    busy)
                        if [ "$runner_calls" -gt 2 ]; then
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
            *"actions/runners/7001"*)
                delete_count=$(cat "${TALO_MOCK_DELETE_COUNTER:?}")
                delete_count=$((delete_count + 1))
                printf '%s\n' "$delete_count" >"$TALO_MOCK_DELETE_COUNTER"
                [ "$delete_count" -gt "${TALO_MOCK_DELETE_FAILURES:-0}" ] || exit 1
                : >"${TALO_MOCK_REGISTRATION_REMOVED:?}"
                ;;
            *) exit 1 ;;
        esac
        ;;
    curl)
        output=
        while [ "$#" -gt 0 ]; do
            if [ "$1" = --output ]; then
                output=$2
                shift 2
                continue
            fi
            shift
        done
        [ -n "$output" ] && [ -f "${TALO_MOCK_ARCHIVE:?}" ]
        cp -- "$TALO_MOCK_ARCHIVE" "$output"
        ;;
    install)
        if [[ " $* " == *" -d "* ]]; then
            /usr/bin/install "$@"
        fi
        ;;
    systemctl)
        if [ "${1:-}" = show ]; then
            case " $* " in
                *" --property=MainPID "*) printf '%s\n' 4242 ;;
                *" --property=ControlGroup "*)
                    printf '%s\n' /system.slice/talo-0001-trusted-runner.service
                    ;;
                *" --property=LoadState "*) printf '%s\n' loaded ;;
                *) exit 1 ;;
            esac
            exit 0
        fi
        if [ "${1:-}" = stop ] && [ "${TALO_MOCK_STOP_FAILURE:-0}" = 1 ]; then
            exit 1
        fi
        if [ "${1:-}" = disable ] && [ "${2:-}" = --now ]; then
            printf '%s\n' disabled >"${TALO_MOCK_SERVICE_STATE:?}"
            exit 0
        fi
        if [ "${1:-}" = enable ] && [ "${2:-}" = --now ]; then
            printf '%s\n' enabled >"${TALO_MOCK_SERVICE_STATE:?}"
            [ "${TALO_MOCK_ENABLE_FAILURE:-0}" != 1 ]
            exit
        fi
        if [ "${1:-}" = is-enabled ]; then
            state=$(cat "${TALO_MOCK_SERVICE_STATE:?}")
            printf '%s\n' "$state"
            [ "$state" = enabled ]
            exit
        fi
        if [ "${1:-}" = is-active ]; then
            state=$(cat "${TALO_MOCK_SERVICE_STATE:?}")
            [ "$state" = enabled ] && exit 0
            printf '%s\n' inactive
            exit 3
        fi
        exit 0
        ;;
    sudo)
        sudo_user=
        if [ "${TALO_MOCK_ENFORCE_TRAVERSAL:-0}" = 1 ] \
            && [[ " $* " == *"/tmp/talo-runner-payload."* ]]; then
            exit 2
        fi
        if [[ "${1:-}" == --preserve-env=* ]]; then
            shift
        fi
        if [ "${1:-}" = -u ]; then
            sudo_user=$2
            shift 2
        fi
        if [ "${1:-}" = -- ]; then
            shift
        fi
        if [ "${TALO_MOCK_REAL_UID:-0}" = 1 ] && [ -n "$sudo_user" ]; then
            /usr/bin/sudo \
                --preserve-env=ACTIONS_RUNNER_INPUT_TOKEN,TALO_MOCK_LOG,TALO_MOCK_CONFIG_CMDLINE,TALO_MOCK_CONFIG_ENV_REMOVED,TALO_MOCK_CONFIG_STARTED,TALO_MOCK_CONFIG_REMOTE_ONLY,TALO_MOCK_CREDENTIALS_TEMPLATE,TALO_MOCK_RSA_TEMPLATE,TALO_MOCK_CONFIG_FAILURE,TALO_MOCK_REPLACE_EXEC \
                -u "$sudo_user" -- "$@"
        else
            "$@"
        fi
        ;;
    *) exit 0 ;;
esac
