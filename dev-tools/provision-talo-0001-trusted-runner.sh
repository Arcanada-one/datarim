#!/usr/bin/env bash
set -euo pipefail

ORG=Arcanada-one
REPOSITORY=Arcanada-one/datarim
REPOSITORY_ID=1207050134
GROUP_NAME=talo-0001-trusted
WORKFLOW_PATH=.github/workflows/talo-0001-trusted-replay.yml
SELECTED_WORKFLOW="$REPOSITORY/$WORKFLOW_PATH@refs/heads/main"
RUNNER_NAME=talo-0001-trusted-arcana-devs
RUNNER_LABEL=talo-0001-trusted
RUNNER_USER=talo-replay
RUNNER_DIR=/srv/talo-0001-trusted/runner
UNIT_NAME=talo-0001-trusted-runner.service
RUNNER_VERSION=2.336.0
RUNNER_ARCHIVE_URL=https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
RUNNER_ARCHIVE_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d
RUNNER_CONFIG_SHA256=4ad01727c3f29a0b6473d625412af6bdefc6c077763a6410f359c764fc0b3ae8
RUNNER_SCRIPT_SHA256=b39d7e0ca921a3189f7fe4e0a2f686b46719d4ccc2647f156f14407ec4517e8f
RUNNER_LISTENER_SHA256=b73c247aa9f0b4198aeb00ae924b7b137c0a717e5dc1066919a80fa4876fdda4
RUNNER_WORKER_SHA256=a23441ed55e5e967ecfb7b9467310693ea73e429a97596ebdc979745cbcdba15
RUNNER_PAYLOAD_TREE_SHA256=802a94df6d2aee3e458620b5a1175f8646f195092081d3285b8b0dd33c8cc8f6
RUNNER_VERIFY_ATTEMPTS=10
RUNNER_VERIFY_INTERVAL_SECONDS=2
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
API_VERSION=2022-11-28

MODE=${1:-}
case "$MODE" in
    --ensure-group|--verify-group|--register-and-start) ;;
    *)
        echo "Usage: $0 --ensure-group|--verify-group|--register-and-start" >&2
        exit 2
        ;;
esac
for command in chmod chown curl find gh git id install jq mkdir mktemp readlink rm \
    sha256sum sleep sort stat sudo systemctl tar wc; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

api() {
    gh api -H "X-GitHub-Api-Version: $API_VERSION" "$@"
}

verify_trusted_main_workflow() {
    local label path remote_blob local_blob
    while IFS='|' read -r label path; do
        if ! remote_blob=$(api "repos/$REPOSITORY/contents/$path?ref=main" --jq .sha 2>/dev/null); then
            echo "ERROR: trusted $label is not present on main" >&2
            exit 1
        fi
        local_blob=$(git -C "$ROOT" hash-object "$ROOT/$path")
        [ "$remote_blob" = "$local_blob" ] || {
            echo "ERROR: trusted $label is not the exact local bootstrap on main" >&2
            exit 1
        }
    done <<EOF
workflow|$WORKFLOW_PATH
provisioner|dev-tools/provision-talo-0001-trusted-runner.sh
runner-unit|dev-tools/systemd/$UNIT_NAME
EOF
}

group_id() {
    api --paginate "orgs/$ORG/actions/runner-groups?per_page=100" \
        --jq ".runner_groups[] | select(.name == \"$GROUP_NAME\") | .id"
}

verify_group() {
    local id=$1 group repositories
    group=$(api "orgs/$ORG/actions/runner-groups/$id")
    jq -e --arg name "$GROUP_NAME" --arg workflow "$SELECTED_WORKFLOW" '
        .name == $name and
        .visibility == "selected" and
        .default == false and
        .allows_public_repositories == true and
        .restricted_to_workflows == true and
        .selected_workflows == [$workflow]
    ' >/dev/null <<<"$group" || {
        echo "ERROR: runner group policy mismatch" >&2
        exit 1
    }
    repositories=$(api "orgs/$ORG/actions/runner-groups/$id/repositories?per_page=100")
    jq -e --argjson repository_id "$REPOSITORY_ID" '
        .total_count == 1 and
        (.repositories | length) == 1 and
        .repositories[0].id == $repository_id
    ' >/dev/null <<<"$repositories" || {
        echo "ERROR: runner group repository scope mismatch" >&2
        exit 1
    }
}

exact_group_runner() {
    local id=$1 required_state=$2 expected_id=${3:-null} runners labels
    runners=$(api "orgs/$ORG/actions/runner-groups/$id/runners?per_page=100")
    labels=$(jq -cn --arg custom "$RUNNER_LABEL" \
        '["self-hosted","Linux","X64",$custom] | sort')
    jq -ce --arg name "$RUNNER_NAME" --arg state "$required_state" \
        --argjson labels "$labels" --argjson expected_id "$expected_id" '
        . as $document |
        if (($document.total_count == 1) and
        (($document.runners | type) == "array") and
        (($document.runners | length) == 1) and
        ($document.runners[0] as $runner |
            (($runner.id | type) == "number") and
            ($runner.id > 0) and
            (($runner.id | floor) == $runner.id) and
            ($expected_id == null or $runner.id == $expected_id) and
            ($runner.name == $name) and
            ($runner.os == "Linux") and
            ($runner.busy == false) and
            (([$runner.labels[].name] | sort) == $labels) and
            (($state == "registered" and ($runner.status == "offline" or $runner.status == "online")) or
             ($state == "online" and $runner.status == "online"))
        )) then $document.runners[0] else empty end
    ' <<<"$runners"
}

group_has_no_runners() {
    local id=$1 runners
    runners=$(api "orgs/$ORG/actions/runner-groups/$id/runners?per_page=100")
    jq -e '.total_count == 0 and .runners == []' >/dev/null <<<"$runners"
}

wait_for_exact_runner() {
    local id=$1 required_state=$2 expected_id=${3:-null} attempt=0 runner
    while [ "$attempt" -lt "$RUNNER_VERIFY_ATTEMPTS" ]; do
        if runner=$(exact_group_runner "$id" "$required_state" "$expected_id"); then
            printf '%s\n' "$runner"
            return 0
        fi
        attempt=$((attempt + 1))
        [ "$attempt" -lt "$RUNNER_VERIFY_ATTEMPTS" ] \
            && sleep "$RUNNER_VERIFY_INTERVAL_SECONDS"
    done
    return 1
}

verify_local_registration() {
    local runner_id=$1 group_id=$2 settings=$RUNNER_DIR/.runner size
    [ -f "$settings" ] && [ ! -L "$settings" ] || return 1
    size=$(stat -c '%s' "$settings" 2>/dev/null) || return 1
    [ "$size" -gt 0 ] && [ "$size" -le 65536 ] || return 1
    jq -e --argjson runner_id "$runner_id" --argjson group_id "$group_id" \
        --arg name "$RUNNER_NAME" --arg group "$GROUP_NAME" \
        --arg url "https://github.com/$ORG" '
        type == "object" and
        .AgentId == $runner_id and
        .AgentName == $name and
        .PoolId == $group_id and
        .PoolName == $group and
        .DisableUpdate == true and
        (.Ephemeral // false) == false and
        .GitHubUrl == $url and
        .WorkFolder == "_work"
    ' >/dev/null "$settings"
}

verify_runner_payload() {
    local path expected actual
    while IFS='|' read -r path expected; do
        path=$RUNNER_DIR/$path
        [ -f "$path" ] && [ ! -L "$path" ] || return 1
        actual=$(sha256sum -- "$path") || return 1
        actual=${actual%% *}
        [ "$actual" = "$expected" ] || return 1
    done <<EOF
config.sh|$RUNNER_CONFIG_SHA256
run.sh|$RUNNER_SCRIPT_SHA256
bin/Runner.Listener|$RUNNER_LISTENER_SHA256
bin/Runner.Worker|$RUNNER_WORKER_SHA256
EOF
}

runner_payload_tree_digest() {
    local root=$1 relative digest target
    (
        cd "$root"
        {
            find bin externals -print0
            printf '%s\0' config.sh env.sh run.sh run-helper.cmd.template \
                run-helper.sh.template safe_sleep.sh
        } | LC_ALL=C sort -z | while IFS= read -r -d '' relative; do
            if [ -L "$relative" ]; then
                target=$(readlink -- "$relative") || exit 1
                printf 'L\0%s\0%s\0' "$relative" "$target"
            elif [ -f "$relative" ]; then
                digest=$(sha256sum -- "$relative") || exit 1
                digest=${digest%% *}
                printf 'F\0%s\0%s\0' "$relative" "$digest"
            elif [ -d "$relative" ]; then
                printf 'D\0%s\0' "$relative"
            else
                exit 1
            fi
        done
    ) | sha256sum
}

verify_runner_payload_tree() {
    local actual
    actual=$(runner_payload_tree_digest "$RUNNER_DIR") || return 1
    actual=${actual%% *}
    [ "$actual" = "$RUNNER_PAYLOAD_TREE_SHA256" ]
}

install_runner_payload() {
    local scratch archive payload
    scratch=$(mktemp -d /tmp/talo-runner-payload.XXXXXX)
    archive=$scratch/actions-runner.tar.gz
    payload=$scratch/payload
    mkdir -p "$payload"
    if ! curl --fail --location --silent --show-error --proto '=https' \
        --tlsv1.2 --max-time 90 --output "$archive" "$RUNNER_ARCHIVE_URL"; then
        rm -rf -- "$scratch"
        echo "ERROR: official runner payload download failed" >&2
        return 1
    fi
    printf '%s  %s\n' "$RUNNER_ARCHIVE_SHA256" "$archive" | sha256sum -c - >/dev/null || {
        rm -rf -- "$scratch"
        echo "ERROR: official runner archive digest mismatch" >&2
        return 1
    }
    tar --extract --gzip --file "$archive" --directory "$payload" --no-same-owner
    if [ -e "$RUNNER_DIR" ] && [ -n "$(find "$RUNNER_DIR" -mindepth 1 -print -quit)" ]; then
        rm -rf -- "$scratch"
        echo "ERROR: unconfigured runner directory is not empty" >&2
        return 1
    fi
    install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$RUNNER_DIR"
    sudo -u "$RUNNER_USER" -- tar --create --directory "$payload" . \
        | sudo -u "$RUNNER_USER" -- tar --extract --directory "$RUNNER_DIR"
    rm -rf -- "$scratch"
    if ! verify_runner_payload || ! verify_runner_payload_tree; then
        echo "ERROR: installed runner payload digest mismatch" >&2
        return 1
    fi
}

ensure_runner_payload() {
    if [ -e "$RUNNER_DIR/.runner" ]; then
        verify_runner_payload
        return
    fi
    if verify_runner_payload && verify_runner_payload_tree; then
        return
    fi
    install_runner_payload
}

harden_runner_payload() {
    local path
    for path in \
        bin externals config.sh env.sh run.sh run-helper.cmd.template \
        run-helper.sh.template safe_sleep.sh; do
        if [ ! -e "$RUNNER_DIR/$path" ] || [ -L "$RUNNER_DIR/$path" ]; then
            echo "ERROR: runner payload hardening inventory mismatch" >&2
            return 1
        fi
        chown -R root:root "$RUNNER_DIR/$path"
        chmod -R a-w "$RUNNER_DIR/$path"
    done
    for path in .runner .credentials .credentials_rsaparams .env .path; do
        if [ -e "$RUNNER_DIR/$path" ]; then
            if [ ! -f "$RUNNER_DIR/$path" ] || [ -L "$RUNNER_DIR/$path" ]; then
                echo "ERROR: runner mutable identity file is invalid" >&2
                return 1
            fi
            chown root:"$RUNNER_USER" "$RUNNER_DIR/$path"
            chmod 0640 "$RUNNER_DIR/$path"
        fi
    done
    install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0750 \
        "$RUNNER_DIR/_diag" "$RUNNER_DIR/_work"
    chown root:root "$RUNNER_DIR"
    chmod 0755 "$RUNNER_DIR"
}

ensure_group() {
    local id group_payload create_payload
    verify_trusted_main_workflow
    id=$(group_id)
    [ "$(wc -w <<<"$id")" -le 1 ] || {
        echo "ERROR: duplicate trusted runner groups" >&2
        exit 1
    }
    group_payload=$(jq -cn --arg name "$GROUP_NAME" --arg workflow "$SELECTED_WORKFLOW" '
        {name:$name,visibility:"selected",allows_public_repositories:true,
         restricted_to_workflows:true,selected_workflows:[$workflow]}
    ')
    if [ -z "$id" ]; then
        create_payload=$(jq -c --argjson repository_id "$REPOSITORY_ID" \
            '. + {selected_repository_ids:[$repository_id]}' <<<"$group_payload")
        id=$(api --method POST "orgs/$ORG/actions/runner-groups" \
            --input - --jq .id <<<"$create_payload")
    else
        api --method PATCH "orgs/$ORG/actions/runner-groups/$id" \
            --input - >/dev/null <<<"$group_payload"
        jq -cn --argjson repository_id "$REPOSITORY_ID" \
            '{selected_repository_ids:[$repository_id]}' |
            api --method PUT "orgs/$ORG/actions/runner-groups/$id/repositories" \
                --input - >/dev/null
    fi
    [[ "$id" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid runner group id" >&2; exit 1; }
    verify_group "$id"
    printf '%s\n' "$id"
}

register_and_start() {
    local id token runner runner_id load_state install_payload=false
    [ "$(id -u)" -eq 0 ] || { echo "ERROR: registration requires root" >&2; exit 1; }
    id=$(ensure_group)
    verify_group "$id"
    if [ -f "$RUNNER_DIR/.runner" ]; then
        runner=$(exact_group_runner "$id" registered) || {
            echo "ERROR: runner is not the exact trusted group member" >&2
            exit 1
        }
        runner_id=$(jq -r .id <<<"$runner")
        verify_local_registration "$runner_id" "$id" || {
            echo "ERROR: local runner registration mismatch" >&2
            exit 1
        }
        verify_runner_payload || {
            echo "ERROR: runner payload digest mismatch" >&2
            exit 1
        }
        verify_runner_payload_tree || {
            echo "ERROR: runner payload tree mismatch" >&2
            exit 1
        }
    else
        group_has_no_runners "$id" || {
            echo "ERROR: unbound remote runner exists in trusted group" >&2
            exit 1
        }
        install_payload=true
        runner_id=
    fi
    load_state=$(systemctl show "$UNIT_NAME" --property=LoadState --value 2>/dev/null) || {
        echo "ERROR: unable to inspect trusted runner service" >&2
        exit 1
    }
    if [ "$load_state" != not-found ]; then
        [ "$load_state" = loaded ] || {
            echo "ERROR: trusted runner service load state is invalid" >&2
            exit 1
        }
        systemctl stop "$UNIT_NAME" 2>/dev/null || {
            echo "ERROR: unable to stop trusted runner service" >&2
            exit 1
        }
    fi
    if [ "$install_payload" = true ]; then
        ensure_runner_payload || {
            echo "ERROR: runner payload provisioning failed" >&2
            exit 1
        }
    fi
    if [ ! -f "$RUNNER_DIR/.runner" ]; then
        token=$(api --method POST "orgs/$ORG/actions/runners/registration-token" --jq .token)
        [ -n "$token" ] || { echo "ERROR: empty runner registration token" >&2; exit 1; }
        sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" --unattended \
            --url "https://github.com/$ORG" --token "$token" \
            --runnergroup "$GROUP_NAME" --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABEL" --work _work --disableupdate
        token=REDACTED
        runner=$(wait_for_exact_runner "$id" registered) || {
            echo "ERROR: runner registration did not reach the exact trusted group" >&2
            exit 1
        }
        runner_id=$(jq -r .id <<<"$runner")
        verify_local_registration "$runner_id" "$id" || {
            echo "ERROR: local runner registration mismatch" >&2
            exit 1
        }
    fi
    harden_runner_payload || {
        echo "ERROR: runner payload hardening failed" >&2
        exit 1
    }
    install -o root -g root -m 0644 \
        "$ROOT/dev-tools/systemd/$UNIT_NAME" "/etc/systemd/system/$UNIT_NAME"
    systemctl daemon-reload || {
        echo "ERROR: trusted runner service reload failed" >&2
        exit 1
    }
    systemctl enable --now "$UNIT_NAME" || {
        systemctl stop "$UNIT_NAME" 2>/dev/null || true
        echo "ERROR: trusted runner service start failed" >&2
        exit 1
    }
    systemctl is-active --quiet "$UNIT_NAME" || {
        systemctl stop "$UNIT_NAME" 2>/dev/null || true
        echo "ERROR: trusted runner service is not active" >&2
        exit 1
    }
    runner=$(wait_for_exact_runner "$id" online "$runner_id") || {
        systemctl stop "$UNIT_NAME" 2>/dev/null || true
        echo "ERROR: trusted runner did not become online and idle" >&2
        exit 1
    }
    verify_local_registration "$(jq -r .id <<<"$runner")" "$id" || {
        systemctl stop "$UNIT_NAME" 2>/dev/null || true
        echo "ERROR: local runner identity changed after start" >&2
        exit 1
    }
}

case "$MODE" in
    --ensure-group) ensure_group >/dev/null ;;
    --verify-group)
        verify_trusted_main_workflow
        current_group_id=$(group_id)
        [[ "$current_group_id" =~ ^[1-9][0-9]*$ ]] || {
            echo "ERROR: trusted runner group missing or duplicated" >&2
            exit 1
        }
        verify_group "$current_group_id"
        ;;
    --register-and-start) register_and_start ;;
esac
