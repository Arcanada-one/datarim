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
for command in gh git install jq sudo systemctl; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

api() {
    gh api -H "X-GitHub-Api-Version: $API_VERSION" "$@"
}

verify_trusted_main_workflow() {
    local remote_blob local_blob
    if ! remote_blob=$(api "repos/$REPOSITORY/contents/$WORKFLOW_PATH?ref=main" --jq .sha 2>/dev/null); then
        echo "ERROR: trusted workflow is not present on main" >&2
        exit 1
    fi
    local_blob=$(git -C "$ROOT" hash-object "$ROOT/$WORKFLOW_PATH")
    [ "$remote_blob" = "$local_blob" ] || {
        echo "ERROR: trusted workflow is not the exact local bootstrap on main" >&2
        exit 1
    }
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

verify_runner_membership() {
    local id=$1 attempts=0 runners
    while [ "$attempts" -lt 10 ]; do
        runners=$(api "orgs/$ORG/actions/runner-groups/$id/runners?per_page=100")
        if jq -e --arg name "$RUNNER_NAME" --arg label "$RUNNER_LABEL" '
            .runners | map(select(
                .name == $name and
                ([.labels[].name] | index($label) != null)
            )) | length == 1
        ' >/dev/null <<<"$runners"; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    echo "ERROR: runner is not a unique member of the trusted group" >&2
    return 1
}

register_and_start() {
    local id token
    [ "$(id -u)" -eq 0 ] || { echo "ERROR: registration requires root" >&2; exit 1; }
    id=$(ensure_group)
    verify_group "$id"
    systemctl stop "$UNIT_NAME" 2>/dev/null || true
    if [ ! -f "$RUNNER_DIR/.runner" ]; then
        token=$(api --method POST "orgs/$ORG/actions/runners/registration-token" --jq .token)
        [ -n "$token" ] || { echo "ERROR: empty runner registration token" >&2; exit 1; }
        sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" --unattended \
            --url "https://github.com/$ORG" --token "$token" \
            --runnergroup "$GROUP_NAME" --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABEL" --work _work
        token=REDACTED
    fi
    verify_runner_membership "$id"
    install -o root -g root -m 0644 \
        "$ROOT/dev-tools/systemd/$UNIT_NAME" "/etc/systemd/system/$UNIT_NAME"
    systemctl daemon-reload
    systemctl enable --now "$UNIT_NAME"
    systemctl is-active --quiet "$UNIT_NAME"
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
