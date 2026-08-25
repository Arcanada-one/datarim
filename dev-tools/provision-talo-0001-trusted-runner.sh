#!/bin/bash -p
set -euo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
IFS=$' \t\n'
export IFS
unset -v BASH_ENV ENV CDPATH GLOBIGNORE
umask 077

ORG=Arcanada-one
REPOSITORY=Arcanada-one/datarim
REPOSITORY_ID=1207050134
GROUP_NAME=talo-0001-trusted
WORKFLOW_PATH=.github/workflows/talo-0001-trusted-replay.yml
SELECTED_WORKFLOW="$REPOSITORY/$WORKFLOW_PATH@refs/heads/main"
RUNNER_NAME=talo-0001-trusted-arcana-devs
RUNNER_LABEL=talo-0001-trusted
RUNNER_USER=talo-replay
RUNNER_HOME=/srv/talo-0001-trusted
RUNNER_DIR=/srv/talo-0001-trusted/runner
PROC_ROOT=/proc
UNIT_NAME=talo-0001-trusted-runner.service
RUNNER_VERSION=2.336.0
RUNNER_ARCHIVE_URL=https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz
# Pinned source contract: CommandSettings ingests ACTIONS_RUNNER_INPUT_*, masks
# Token, and removes the input from the process environment before use.
# https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/CommandSettings.cs
# sha256:937f6552579f7d1eeb0a6d0201586781eb3e2e5ea2ab3878429076560e0cab08
# RunnerSettings/OAuth/RSA identity authority at the same pinned tag:
# https://github.com/actions/runner/blob/v2.336.0/src/Runner.Common/ConfigurationStore.cs
# sha256:5eca29c4f3ce56861680058dbc5e64ec7222421bdb7281f1d502717a235c56a9
# https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/Configuration/ConfigurationManager.cs
# sha256:beb6d17709f931808b71b8210ee170951a99fac2342110b3600fb8a1b46d740c
# https://github.com/actions/runner/blob/v2.336.0/src/Runner.Common/CredentialData.cs
# sha256:495cac8f884cf458ecb186820aaac0211f0fd1090015ad1cdbb9f17f314e2de1
# https://github.com/actions/runner/blob/v2.336.0/src/Runner.Listener/Configuration/IRSAKeyManager.cs
# sha256:8176f9a5885eb100aa1dec7f5a3222b6e646684e090ff2eb8c2b235fad69bf96
RUNNER_ARCHIVE_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d
RUNNER_CONFIG_SHA256=4ad01727c3f29a0b6473d625412af6bdefc6c077763a6410f359c764fc0b3ae8
RUNNER_SCRIPT_SHA256=b39d7e0ca921a3189f7fe4e0a2f686b46719d4ccc2647f156f14407ec4517e8f
RUNNER_LISTENER_SHA256=b73c247aa9f0b4198aeb00ae924b7b137c0a717e5dc1066919a80fa4876fdda4
RUNNER_WORKER_SHA256=a23441ed55e5e967ecfb7b9467310693ea73e429a97596ebdc979745cbcdba15
RUNNER_PAYLOAD_TREE_SHA256=802a94df6d2aee3e458620b5a1175f8646f195092081d3285b8b0dd33c8cc8f6
RUNNER_VERIFY_ATTEMPTS=10
RUNNER_VERIFY_INTERVAL_SECONDS=2
RUNNER_DELETE_ATTEMPTS=3
script_directory=${BASH_SOURCE[0]%/*}
[ "$script_directory" != "${BASH_SOURCE[0]}" ] || script_directory=.
ROOT=$(builtin cd -- "$script_directory/.." && builtin pwd -P)
API_VERSION=2022-11-28
TRUSTED_MAIN_COMMIT=
TRUSTED_BOOTSTRAP_ROOT=
TRUSTED_SOURCE_ROOT=$ROOT
BOOTSTRAP_PHASE=${TALO_TRUSTED_BOOTSTRAP_PHASE:-loader}

MODE=${1:-}
case "$MODE" in
    --ensure-group|--verify-group|--register-and-start) ;;
    *)
        echo "Usage: $0 --ensure-group|--verify-group|--register-and-start" >&2
        exit 2
        ;;
esac
for command in awk chmod chown curl env find getent gh git id install jq mkdir \
    mktemp mv pgrep python3 readlink rm sha256sum sleep sort stat sudo systemctl \
    tar wc; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

api() {
    gh api -H "X-GitHub-Api-Version: $API_VERSION" "$@"
}

bootstrap_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
        -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
        -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS -u GIT_INDEX_FILE \
        -u GIT_NAMESPACE -u GIT_SHALLOW_FILE \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git -C "$TRUSTED_SOURCE_ROOT" "$@"
}

resolve_live_main_commit() {
    local response
    response=$(api "repos/$REPOSITORY/git/ref/heads/main") || return 1
    jq -er --arg repository "$REPOSITORY" '
        select(type == "object" and (keys | sort) == ["node_id","object","ref","url"])
        | select(.ref == "refs/heads/main")
        | select(.node_id | type == "string" and length > 0)
        | select(.url == ("https://api.github.com/repos/" + $repository + "/git/refs/heads/main"))
        | .object
        | select(type == "object" and (keys | sort) == ["sha","type","url"])
        | select(.type == "commit")
        | select(.url == ("https://api.github.com/repos/" + $repository + "/git/commits/" + .sha))
        | .sha
        | select(type == "string" and test("^[0-9a-f]{40}$"))
    ' <<<"$response"
}

cleanup_trusted_bootstrap() {
    if [[ "$TRUSTED_BOOTSTRAP_ROOT" == /tmp/talo-trusted-bootstrap.* ]] \
        && [ -d "$TRUSTED_BOOTSTRAP_ROOT" ] \
        && [ ! -L "$TRUSTED_BOOTSTRAP_ROOT" ] \
        && [ "$(stat -c '%u:%g:%a' "$TRUSTED_BOOTSTRAP_ROOT" 2>/dev/null || true)" = 0:0:700 ]; then
        rm -rf -- "$TRUSTED_BOOTSTRAP_ROOT"
    fi
}

materialize_trusted_bootstrap_blob() {
    local commit=$1 relative=$2 destination entry mode type object_id recorded_path
    local expected_mode file_mode materialized_object_id object_digest \
        materialized_digest
    case "$relative" in
        /*|*..*|*//*|*:*) return 1 ;;
    esac
    entry=$(bootstrap_git ls-tree "$commit" -- "$relative") || return 1
    [ -n "$entry" ] && [[ "$entry" != *$'\n'* ]] || return 1
    IFS=$' \t' read -r mode type object_id recorded_path <<<"$entry"
    expected_mode=100644
    file_mode=0400
    if [ "$relative" = dev-tools/provision-talo-0001-trusted-runner.sh ]; then
        expected_mode=100755
        file_mode=0500
    fi
    [ "$mode" = "$expected_mode" ] && [ "$type" = blob ] \
        && [[ "$object_id" =~ ^[0-9a-f]{40}$ ]] \
        && [ "$recorded_path" = "$relative" ] || return 1
    destination=$TRUSTED_BOOTSTRAP_ROOT/$relative
    install -d -o root -g root -m 0700 "$(dirname "$destination")" \
        || return 1
    install -o root -g root -m "$file_mode" /dev/null "$destination" || return 1
    bootstrap_git cat-file blob "$object_id" >"$destination" || return 1
    [ -f "$destination" ] && [ ! -L "$destination" ] \
        && [ "$(stat -c '%u:%g:%a' "$destination")" = "0:0:${file_mode#0}" ] \
        || return 1
    materialized_object_id=$(bootstrap_git hash-object -- "$destination") \
        || return 1
    [ "$materialized_object_id" = "$object_id" ] || return 1
    object_digest=$(bootstrap_git cat-file blob "$object_id" \
        | sha256sum | cut -d' ' -f1) || return 1
    materialized_digest=$(sha256sum -- "$destination" | cut -d' ' -f1) \
        || return 1
    [ "$object_digest" = "$materialized_digest" ]
}

verify_trusted_bootstrap_blob() {
    local commit=$1 relative=$2 staged entry mode type object_id recorded_path
    local expected_mode file_mode staged_object_id object_digest staged_digest
    case "$relative" in
        /*|*..*|*//*|*:*) return 1 ;;
    esac
    entry=$(bootstrap_git ls-tree "$commit" -- "$relative") || return 1
    [ -n "$entry" ] && [[ "$entry" != *$'\n'* ]] || return 1
    IFS=$' \t' read -r mode type object_id recorded_path <<<"$entry"
    expected_mode=100644
    file_mode=400
    if [ "$relative" = dev-tools/provision-talo-0001-trusted-runner.sh ]; then
        expected_mode=100755
        file_mode=500
    fi
    [ "$mode" = "$expected_mode" ] && [ "$type" = blob ] \
        && [[ "$object_id" =~ ^[0-9a-f]{40}$ ]] \
        && [ "$recorded_path" = "$relative" ] || return 1
    staged=$TRUSTED_BOOTSTRAP_ROOT/$relative
    [ -f "$staged" ] && [ ! -L "$staged" ] \
        && [ "$(stat -c '%u:%g:%a' "$staged")" = "0:0:$file_mode" ] \
        || return 1
    staged_object_id=$(bootstrap_git hash-object -- "$staged") || return 1
    [ "$staged_object_id" = "$object_id" ] || return 1
    object_digest=$(bootstrap_git cat-file blob "$object_id" \
        | sha256sum | cut -d' ' -f1) || return 1
    staged_digest=$(sha256sum -- "$staged" | cut -d' ' -f1) || return 1
    [ "$object_digest" = "$staged_digest" ]
}

materialize_trusted_main_bootstrap() {
    local resolved_commit verified_commit artifact_label relative
    resolved_commit=$(resolve_live_main_commit) || {
        echo "ERROR: trusted main ref could not be resolved" >&2
        return 1
    }
    verified_commit=$(bootstrap_git rev-parse "$resolved_commit^{commit}") || {
        echo "ERROR: trusted main commit is unavailable locally" >&2
        return 1
    }
    [ "$verified_commit" = "$resolved_commit" ] || return 1
    TRUSTED_MAIN_COMMIT=$resolved_commit
    TRUSTED_BOOTSTRAP_ROOT=$(mktemp -d /tmp/talo-trusted-bootstrap.XXXXXX) \
        || return 1
    chown root:root "$TRUSTED_BOOTSTRAP_ROOT" || return 1
    chmod 0700 "$TRUSTED_BOOTSTRAP_ROOT" || return 1
    [ "$(stat -c '%u:%g:%a' "$TRUSTED_BOOTSTRAP_ROOT")" = 0:0:700 ] \
        || return 1
    trap cleanup_trusted_bootstrap EXIT
    while IFS='|' read -r artifact_label relative; do
        [ -n "$artifact_label" ] || return 1
        materialize_trusted_bootstrap_blob "$resolved_commit" "$relative" || {
            echo "ERROR: trusted bootstrap Git object rejected: $relative" >&2
            return 1
        }
    done <<EOF
workflow|$WORKFLOW_PATH
provisioner|dev-tools/provision-talo-0001-trusted-runner.sh
runner-unit|dev-tools/systemd/$UNIT_NAME
EOF
}

validate_sealed_bootstrap() {
    local current_main verified_commit artifact_label relative source_path
    TRUSTED_MAIN_COMMIT=${TALO_TRUSTED_MAIN_COMMIT:-}
    TRUSTED_BOOTSTRAP_ROOT=${TALO_TRUSTED_BOOTSTRAP_ROOT:-}
    TRUSTED_SOURCE_ROOT=${TALO_TRUSTED_SOURCE_ROOT:-}
    if ! [[ "$TRUSTED_MAIN_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
        || ! [[ "$TRUSTED_BOOTSTRAP_ROOT" == /tmp/talo-trusted-bootstrap.* ]] \
        || ! [[ "$TRUSTED_SOURCE_ROOT" == /* ]] \
        || [ ! -d "$TRUSTED_BOOTSTRAP_ROOT" ] \
        || [ -L "$TRUSTED_BOOTSTRAP_ROOT" ] \
        || [ "$(stat -c '%u:%g:%a' "$TRUSTED_BOOTSTRAP_ROOT" 2>/dev/null || true)" != 0:0:700 ]; then
        echo "ERROR: sealed bootstrap identity rejected" >&2
        return 1
    fi
    source_path=$(readlink -f -- "${BASH_SOURCE[0]}") || return 1
    [ "$source_path" = "$TRUSTED_BOOTSTRAP_ROOT/dev-tools/provision-talo-0001-trusted-runner.sh" ] \
        || { echo "ERROR: provisioner is not executing from sealed bootstrap" >&2; return 1; }
    trap cleanup_trusted_bootstrap EXIT
    current_main=$(resolve_live_main_commit) || {
        echo "ERROR: live main revalidation failed before provisioning" >&2
        return 1
    }
    [ "$current_main" = "$TRUSTED_MAIN_COMMIT" ] || {
        echo "ERROR: trusted main advanced before provisioning" >&2
        return 1
    }
    verified_commit=$(bootstrap_git rev-parse "$TRUSTED_MAIN_COMMIT^{commit}") \
        || return 1
    [ "$verified_commit" = "$TRUSTED_MAIN_COMMIT" ] || return 1
    while IFS='|' read -r artifact_label relative; do
        [ -n "$artifact_label" ] || return 1
        verify_trusted_bootstrap_blob "$TRUSTED_MAIN_COMMIT" "$relative" || {
            echo "ERROR: sealed bootstrap Git object rejected: $relative" >&2
            return 1
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
            (($state == "cleanup") or ($runner.busy == false)) and
            (([$runner.labels[].name] | sort) == $labels) and
            (($state == "cleanup" and ($runner.status == "offline" or $runner.status == "online")) or
             ($state == "registered" and ($runner.status == "offline" or $runner.status == "online")) or
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

wait_for_no_runners() {
    local id=$1 attempt=0 consecutive=0
    while [ "$attempt" -lt "$RUNNER_VERIFY_ATTEMPTS" ]; do
        if group_has_no_runners "$id"; then
            consecutive=$((consecutive + 1))
            [ "$consecutive" -ge 3 ] && return 0
        else
            consecutive=0
        fi
        attempt=$((attempt + 1))
        [ "$attempt" -lt "$RUNNER_VERIFY_ATTEMPTS" ] \
            && sleep "$RUNNER_VERIFY_INTERVAL_SECONDS"
    done
    return 1
}

validate_registration_identity_files() {
    local runner_id=$1 group_id=$2
    python3 - "$RUNNER_DIR/.runner" "$RUNNER_DIR/.credentials" \
        "$RUNNER_DIR/.credentials_rsaparams" "$runner_id" "$group_id" \
        "$RUNNER_NAME" "$GROUP_NAME" "$ORG" 2>/dev/null <<'PY'
import base64
import json
import os
from pathlib import Path
import re
import stat
import sys
from urllib.parse import urlsplit
import uuid

settings_path, credentials_path, rsa_path = map(Path, sys.argv[1:4])
runner_id, group_id = map(int, sys.argv[4:6])
runner_name, group_name, org = sys.argv[6:9]


def pairs(pairs_value):
    result = {}
    for key, value in pairs_value:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def load(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= 65536:
            raise ValueError("invalid identity file")
        payload = os.read(descriptor, info.st_size + 1)
        if len(payload) != info.st_size:
            raise ValueError("identity file changed while reading")
    finally:
        os.close(descriptor)
    return json.loads(payload, object_pairs_hook=pairs)


def strict_url(value, endpoint):
    if not isinstance(value, str):
        raise ValueError("URL is not a string")
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or parsed.username is not None
            or parsed.password is not None or parsed.port is not None
            or parsed.query or parsed.fragment):
        raise ValueError("unsafe URL structure")
    host = parsed.hostname or ""
    if endpoint == "broker":
        if value != "https://broker.actions.githubusercontent.com/":
            raise ValueError("unexpected broker URL")
    elif endpoint == "tenant":
        if (not re.fullmatch(r"pipelinesghub[a-z0-9-]+\.actions\.githubusercontent\.com", host)
                or not re.fullmatch(r"/[A-Za-z0-9_-]{16,}/", parsed.path)):
            raise ValueError("unexpected tenant URL")
    else:
        if (not re.fullmatch(r"[a-z0-9-]+\.actions\.githubusercontent\.com", host)
                or not parsed.path.startswith("/") or parsed.path == "/"):
            raise ValueError("unexpected authorization URL")


settings = load(settings_path)
required_settings = {
    "AgentId", "AgentName", "PoolId", "PoolName", "DisableUpdate",
    "ServerUrl", "GitHubUrl", "WorkFolder", "UseV2Flow",
    "UseRunnerAdminFlow", "ServerUrlV2",
}
optional_settings = {"Ephemeral", "SkipSessionRecover", "MonitorSocketAddress"}
if not isinstance(settings, dict) or not required_settings <= settings.keys():
    raise ValueError("missing runner setting")
if not settings.keys() <= required_settings | optional_settings:
    raise ValueError("unknown runner setting")
if settings.get("Ephemeral", False) is not False:
    raise ValueError("ephemeral runner is forbidden")
if settings.get("SkipSessionRecover", False) is not False:
    raise ValueError("session recovery cannot be skipped")
if settings.get("MonitorSocketAddress") not in (None, ""):
    raise ValueError("monitor socket override is forbidden")
if not (
    settings["AgentId"] == runner_id
    and settings["AgentName"] == runner_name
    and settings["PoolId"] == group_id
    and settings["PoolName"] == group_name
    and settings["DisableUpdate"] is True
    and settings["GitHubUrl"] == f"https://github.com/{org}"
    and settings["WorkFolder"] == "_work"
    and settings["UseV2Flow"] is True
    and settings["UseRunnerAdminFlow"] is True
):
    raise ValueError("runner identity mismatch")
strict_url(settings["ServerUrl"], "tenant")
strict_url(settings["ServerUrlV2"], "broker")

credentials = load(credentials_path)
if not isinstance(credentials, dict) or set(credentials) != {"Scheme", "Data"}:
    raise ValueError("credential root mismatch")
if credentials["Scheme"] != "OAuth" or not isinstance(credentials["Data"], dict):
    raise ValueError("credential scheme mismatch")
data = credentials["Data"]
required_data = {"clientId", "authorizationUrl", "requireFipsCryptography"}
optional_data = {"enableAuthMigrationByDefault", "authorizationUrlV2"}
if not required_data <= data.keys() or not data.keys() <= required_data | optional_data:
    raise ValueError("credential data mismatch")
client_id = uuid.UUID(data["clientId"])
if client_id.int == 0 or str(client_id) != data["clientId"].lower():
    raise ValueError("credential client identity mismatch")
if data["requireFipsCryptography"] not in {"True", "False"}:
    raise ValueError("credential FIPS value mismatch")
strict_url(data["authorizationUrl"], "authorization")
migration_present = "enableAuthMigrationByDefault" in data or "authorizationUrlV2" in data
if migration_present:
    if (data.get("enableAuthMigrationByDefault") != "true"
            or "authorizationUrlV2" not in data):
        raise ValueError("credential migration mismatch")
    strict_url(data["authorizationUrlV2"], "broker")

rsa = load(rsa_path)
lengths = {"d": 256, "dp": 128, "dq": 128, "inverseQ": 128,
           "modulus": 256, "p": 128, "q": 128}
if not isinstance(rsa, dict) or set(rsa) != set(lengths) | {"exponent"}:
    raise ValueError("RSA identity shape mismatch")
for key, expected_length in lengths.items():
    value = base64.b64decode(rsa[key], validate=True)
    if len(value) != expected_length or not any(value):
        raise ValueError("RSA identity value mismatch")
if base64.b64decode(rsa["exponent"], validate=True) != b"\x01\x00\x01":
    raise ValueError("RSA exponent mismatch")
PY
}

registration_identity_digest() {
    local path=$1 actual
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    actual=$(sha256sum -- "$path") || return 1
    printf '%s\n' "${actual%% *}"
}

verify_registration_identity_seal() {
    local runner_id=$1 group_id=$2 seal=$RUNNER_DIR/.talo-registration-seal \
        runner_digest credential_digest rsa_digest size
    [ -f "$seal" ] && [ ! -L "$seal" ] || return 1
    size=$(stat -c '%s' "$seal" 2>/dev/null) || return 1
    [ "$size" -gt 0 ] && [ "$size" -le 4096 ] || return 1
    runner_digest=$(registration_identity_digest "$RUNNER_DIR/.runner") || return 1
    credential_digest=$(registration_identity_digest "$RUNNER_DIR/.credentials") || return 1
    rsa_digest=$(registration_identity_digest "$RUNNER_DIR/.credentials_rsaparams") || return 1
    jq -e --argjson runner_id "$runner_id" --argjson group_id "$group_id" \
        --arg runner "$runner_digest" --arg credentials "$credential_digest" \
        --arg rsa "$rsa_digest" '
        type == "object" and
        (keys | sort) == ["credentials_sha256","group_id","rsa_sha256","runner_id","runner_sha256","schema_version"] and
        .schema_version == 1 and .runner_id == $runner_id and
        .group_id == $group_id and .runner_sha256 == $runner and
        .credentials_sha256 == $credentials and .rsa_sha256 == $rsa
    ' >/dev/null "$seal"
}

write_registration_identity_seal() {
    local runner_id=$1 group_id=$2 seal=$RUNNER_DIR/.talo-registration-seal \
        temporary runner_digest credential_digest rsa_digest
    runner_digest=$(registration_identity_digest "$RUNNER_DIR/.runner") || return 1
    credential_digest=$(registration_identity_digest "$RUNNER_DIR/.credentials") || return 1
    rsa_digest=$(registration_identity_digest "$RUNNER_DIR/.credentials_rsaparams") || return 1
    temporary=$(mktemp "$RUNNER_DIR/.talo-registration-seal.XXXXXXXX") || return 1
    if ! jq -n --argjson runner_id "$runner_id" --argjson group_id "$group_id" \
        --arg runner "$runner_digest" --arg credentials "$credential_digest" \
        --arg rsa "$rsa_digest" \
        '{schema_version:1,runner_id:$runner_id,group_id:$group_id,runner_sha256:$runner,credentials_sha256:$credentials,rsa_sha256:$rsa}' \
        >"$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    chown root:root "$temporary"
    chmod 0600 "$temporary"
    mv -f -- "$temporary" "$seal"
}

lock_registration_identity_files() {
    local path
    for path in .runner .credentials .credentials_rsaparams; do
        [ -f "$RUNNER_DIR/$path" ] && [ ! -L "$RUNNER_DIR/$path" ] || return 1
        chown root:"$RUNNER_USER" "$RUNNER_DIR/$path"
        chmod 0640 "$RUNNER_DIR/$path"
    done
}

verify_local_registration_core() {
    local runner_id=$1 group_id=$2
    validate_registration_identity_files "$runner_id" "$group_id"
}

verify_local_registration() {
    local runner_id=$1 group_id=$2
    verify_local_registration_core "$runner_id" "$group_id" \
        && verify_registration_identity_seal "$runner_id" "$group_id"
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

verify_runner_account() {
    local record name _password uid gid _gecos home shell extra
    record=$(getent passwd "$RUNNER_USER") || return 1
    [ "$(wc -l <<<"$record")" -eq 1 ] || return 1
    IFS=: read -r name _password uid gid _gecos home shell extra <<<"$record"
    [ "$name" = "$RUNNER_USER" ] && [ -z "$extra" ] \
        && [[ "$uid" =~ ^[1-9][0-9]*$ ]] \
        && [[ "$gid" =~ ^[1-9][0-9]*$ ]] \
        && [ "$home" = "$RUNNER_HOME" ] \
        && { [ "$shell" = /usr/sbin/nologin ] || [ "$shell" = /sbin/nologin ]; }
}

assert_runner_user_quiescent() {
    local status
    if pgrep -u "$RUNNER_USER" >/dev/null 2>&1; then
        echo "ERROR: trusted runner identity is not quiescent" >&2
        return 1
    else
        status=$?
    fi
    [ "$status" -eq 1 ] || {
        echo "ERROR: trusted runner process inspection failed" >&2
        return 1
    }
}

verify_runner_payload_ownership() {
    [ "$(stat -c '%u:%g:%a' "$RUNNER_DIR")" = 0:0:755 ] || return 1
    verify_root_owned_executable_inventory
}

verify_root_owned_executable_inventory() {
    local path owner mode
    for path in \
        bin externals config.sh env.sh run.sh run-helper.cmd.template \
        run-helper.sh.template safe_sleep.sh; do
        if [ ! -e "$RUNNER_DIR/$path" ] || [ -L "$RUNNER_DIR/$path" ]; then
            echo "ERROR: executable payload inventory is incomplete: $path" >&2
            return 1
        fi
    done
    while IFS= read -r -d '' path; do
        owner=$(stat -c '%u:%g' -- "$path") || return 1
        [ "$owner" = 0:0 ] || {
            echo "ERROR: executable payload is not root-owned: $path" >&2
            return 1
        }
        if [ ! -L "$path" ]; then
            mode=$(stat -c '%a' -- "$path") || return 1
            (( (8#$mode & 022) == 0 )) || {
                echo "ERROR: executable payload is writable: $path" >&2
                return 1
            }
        fi
    done < <(find \
        "$RUNNER_DIR/bin" "$RUNNER_DIR/externals" \
        "$RUNNER_DIR/config.sh" "$RUNNER_DIR/env.sh" "$RUNNER_DIR/run.sh" \
        "$RUNNER_DIR/run-helper.cmd.template" \
        "$RUNNER_DIR/run-helper.sh.template" "$RUNNER_DIR/safe_sleep.sh" \
        -print0)
}

harden_executable_payload() {
    local path
    for path in \
        bin externals config.sh env.sh run.sh run-helper.cmd.template \
        run-helper.sh.template safe_sleep.sh; do
        if [ ! -e "$RUNNER_DIR/$path" ] || [ -L "$RUNNER_DIR/$path" ]; then
            echo "ERROR: runner executable payload inventory mismatch" >&2
            return 1
        fi
        chown -R root:root "$RUNNER_DIR/$path"
        chmod -R a-w "$RUNNER_DIR/$path"
    done
    chown root:root "$RUNNER_DIR"
    chmod 0755 "$RUNNER_DIR"
    chmod g-s,o-t "$RUNNER_DIR"
    install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0750 \
        "$RUNNER_DIR/_diag" "$RUNNER_DIR/_work"
    verify_runner_payload && verify_runner_payload_tree \
        && verify_runner_payload_ownership
}

open_registration_directory() {
    local runner_gid
    local_registration_absent || return 1
    runner_gid=$(id -g "$RUNNER_USER") || return 1
    [[ "$runner_gid" =~ ^[1-9][0-9]*$ ]] || return 1
    chown root:"$RUNNER_USER" "$RUNNER_DIR"
    chmod 3775 "$RUNNER_DIR"
    [ "$(stat -c '%u:%g:%a' "$RUNNER_DIR")" = "0:$runner_gid:3775" ] \
        && verify_root_owned_executable_inventory
}

seal_registration_directory() {
    local state
    chmod 0755 "$RUNNER_DIR" || return 1
    chmod g-s,o-t "$RUNNER_DIR" || return 1
    chown root:root "$RUNNER_DIR" || return 1
    state=$(stat -c '%u:%g:%a' "$RUNNER_DIR") || return 1
    [ "$state" = 0:0:755 ] || {
        echo "ERROR: registration directory seal mismatch: $state" >&2
        return 1
    }
    verify_root_owned_executable_inventory
}

seal_interrupted_registration_directory() {
    if [ ! -e "$RUNNER_DIR" ] && [ ! -L "$RUNNER_DIR" ]; then
        return 0
    fi
    [ -d "$RUNNER_DIR" ] && [ ! -L "$RUNNER_DIR" ] \
        && seal_registration_directory
}

install_runner_payload() {
    local scratch archive
    scratch=$(mktemp -d /tmp/talo-runner-payload.XXXXXX)
    archive=$scratch/actions-runner.tar.gz
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
    if [ -e "$RUNNER_DIR" ] && [ -n "$(find "$RUNNER_DIR" -mindepth 1 -print -quit)" ]; then
        rm -rf -- "$scratch"
        echo "ERROR: unconfigured runner directory is not empty" >&2
        return 1
    fi
    install -d -o root -g root -m 0755 "$RUNNER_DIR"
    if ! tar --extract --gzip --file "$archive" --directory "$RUNNER_DIR" \
        --no-same-owner; then
        rm -rf -- "$scratch"
        echo "ERROR: official runner payload extraction failed" >&2
        return 1
    fi
    rm -rf -- "$scratch"
    if ! harden_executable_payload; then
        echo "ERROR: installed runner payload digest mismatch" >&2
        return 1
    fi
}

disable_runner_service() {
    local enabled_state active_state
    systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
    enabled_state=$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null || true)
    active_state=$(systemctl is-active "$UNIT_NAME" 2>/dev/null || true)
    case "$enabled_state" in
        disabled|not-found) ;;
        *) return 1 ;;
    esac
    case "$active_state" in
        inactive|failed|unknown) ;;
        *) return 1 ;;
    esac
}

rollback_new_registration() {
    local id=$1 pre_registration_empty=$2 known_runner_id=${3:-}
    [ "$pre_registration_empty" = true ] || return 1
    remove_remote_new_registration "$id" "$known_runner_id" || return 1
    rm -f -- "$RUNNER_DIR/.runner" "$RUNNER_DIR/.credentials" \
        "$RUNNER_DIR/.credentials_rsaparams" "$RUNNER_DIR/.env" \
        "$RUNNER_DIR/.path" "$RUNNER_DIR/.talo-registration-seal"
}

remove_remote_new_registration() {
    local id=$1 known_runner_id=${2:-} attempt=0 runner cleanup_runner_id \
        expected_id
    if [ -z "$known_runner_id" ] && [ -f "$RUNNER_DIR/.runner" ]; then
        known_runner_id=$(jq -er \
            '.AgentId | select(type == "number" and . > 0 and floor == .)' \
            "$RUNNER_DIR/.runner" 2>/dev/null || true)
    fi
    expected_id=${known_runner_id:-null}
    while [ "$attempt" -lt "$RUNNER_DELETE_ATTEMPTS" ]; do
        if group_has_no_runners "$id"; then
            wait_for_no_runners "$id" && return 0
        else
            runner=$(exact_group_runner "$id" cleanup "$expected_id") || return 1
            cleanup_runner_id=$(jq -r .id <<<"$runner")
            if api --method DELETE \
                "orgs/$ORG/actions/runners/$cleanup_runner_id" >/dev/null; then
                wait_for_no_runners "$id" && return 0
            fi
        fi
        attempt=$((attempt + 1))
        [ "$attempt" -lt "$RUNNER_DELETE_ATTEMPTS" ] \
            && sleep "$RUNNER_VERIFY_INTERVAL_SECONDS"
    done
    return 1
}

abort_runner_transaction() {
    local id=$1 fresh_registration=$2 pre_registration_empty=$3 \
        known_runner_id=$4 message=$5 rollback_failed=false
    disable_runner_service || rollback_failed=true
    seal_registration_directory || rollback_failed=true
    if [ "$fresh_registration" = true ]; then
        rollback_new_registration "$id" "$pre_registration_empty" \
            "$known_runner_id" \
            || rollback_failed=true
    fi
    if [ "$rollback_failed" = true ]; then
        echo "ERROR: trusted runner rollback could not prove fail-closed state" >&2
    fi
    echo "ERROR: $message" >&2
    exit 1
}

ensure_runner_payload() {
    if [ -e "$RUNNER_DIR/.runner" ]; then
        verify_runner_payload && verify_runner_payload_tree \
            && verify_runner_payload_ownership
        return
    fi
    if verify_runner_payload && verify_runner_payload_tree; then
        harden_executable_payload
        return
    fi
    install_runner_payload
}

harden_runner_payload() {
    local path
    harden_executable_payload || return 1
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
    if [ ! -f "$RUNNER_DIR/.talo-registration-seal" ] \
        || [ -L "$RUNNER_DIR/.talo-registration-seal" ]; then
        echo "ERROR: runner registration seal is invalid" >&2
        return 1
    fi
    chown root:root "$RUNNER_DIR/.talo-registration-seal"
    chmod 0600 "$RUNNER_DIR/.talo-registration-seal"
}

local_registration_absent() {
    local path
    for path in .runner .credentials .credentials_rsaparams .env .path \
        .talo-registration-seal; do
        if [ -e "$RUNNER_DIR/$path" ] || [ -L "$RUNNER_DIR/$path" ]; then
            return 1
        fi
    done
}

bind_pre_reconcile_roster() {
    local id=$1 runner runner_id
    if [ -z "$id" ]; then
        local_registration_absent || {
            echo "ERROR: local runner identity exists without trusted group" >&2
            return 1
        }
        return 0
    fi
    if [ -f "$RUNNER_DIR/.runner" ] && [ ! -L "$RUNNER_DIR/.runner" ]; then
        runner=$(exact_group_runner "$id" registered) || {
            echo "ERROR: runner is not the exact trusted group member" >&2
            return 1
        }
        runner_id=$(jq -r .id <<<"$runner")
        verify_local_registration "$runner_id" "$id" || {
            echo "ERROR: local runner registration mismatch" >&2
            return 1
        }
        verify_runner_payload || {
            echo "ERROR: runner payload digest mismatch" >&2
            return 1
        }
        verify_runner_payload_tree || {
            echo "ERROR: runner payload tree mismatch" >&2
            return 1
        }
        harden_executable_payload || {
            echo "ERROR: runner payload ownership mismatch" >&2
            return 1
        }
        return 0
    fi
    local_registration_absent || {
        echo "ERROR: incomplete local runner identity exists before reconciliation" >&2
        return 1
    }
    group_has_no_runners "$id" || {
        echo "ERROR: pre-reconciliation roster is not empty" >&2
        return 1
    }
}

ensure_group() {
    local id
    [ "$(id -u)" -eq 0 ] || {
        echo "ERROR: runner group reconciliation requires root" >&2
        return 1
    }
    if [ -z "$TRUSTED_MAIN_COMMIT" ] || [ -z "$TRUSTED_BOOTSTRAP_ROOT" ]; then
        echo "ERROR: trusted bootstrap was not materialized" >&2
        return 1
    fi
    if ! id=$(group_id); then
        echo "ERROR: trusted runner group lookup failed" >&2
        return 1
    fi
    [ "$(wc -w <<<"$id")" -le 1 ] || {
        echo "ERROR: duplicate trusted runner groups" >&2
        return 1
    }
    if [ -n "$id" ] && ! [[ "$id" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: invalid runner group id" >&2
        return 1
    fi
    stop_and_disable_runner_service || return 1
    seal_interrupted_registration_directory || {
        echo "ERROR: interrupted runner registration could not be resealed" >&2
        return 1
    }
    verify_runner_account || {
        echo "ERROR: runner account boundary mismatch before reconciliation" >&2
        return 1
    }
    assert_runner_user_quiescent || {
        echo "ERROR: runner identity is not quiescent before reconciliation" >&2
        return 1
    }
    bind_pre_reconcile_roster "$id" || return 1
    reconcile_group "$id"
}

reconcile_group() {
    local id=$1 group_payload create_payload
    if ! group_payload=$(jq -cn --arg name "$GROUP_NAME" \
        --arg workflow "$SELECTED_WORKFLOW" '
        {name:$name,visibility:"selected",allows_public_repositories:true,
         restricted_to_workflows:true,selected_workflows:[$workflow]}
    '); then
        echo "ERROR: trusted runner group policy encoding failed" >&2
        return 1
    fi
    if [ -z "$id" ]; then
        if ! create_payload=$(jq -c --argjson repository_id "$REPOSITORY_ID" \
            '. + {selected_repository_ids:[$repository_id]}' \
            <<<"$group_payload"); then
            echo "ERROR: trusted runner group creation payload failed" >&2
            return 1
        fi
        if ! id=$(api --method POST "orgs/$ORG/actions/runner-groups" \
            --input - --jq .id <<<"$create_payload"); then
            echo "ERROR: trusted runner group creation failed" >&2
            return 1
        fi
    else
        if ! api --method PATCH "orgs/$ORG/actions/runner-groups/$id" \
            --input - >/dev/null <<<"$group_payload"; then
            echo "ERROR: trusted runner group policy update failed" >&2
            return 1
        fi
        if ! jq -cn --argjson repository_id "$REPOSITORY_ID" \
            '{selected_repository_ids:[$repository_id]}' |
            api --method PUT "orgs/$ORG/actions/runner-groups/$id/repositories" \
                --input - >/dev/null; then
            echo "ERROR: trusted runner group repository update failed" >&2
            return 1
        fi
    fi
    [[ "$id" =~ ^[1-9][0-9]*$ ]] || {
        echo "ERROR: invalid runner group id" >&2
        return 1
    }
    verify_group "$id"
    printf '%s\n' "$id"
}

stop_and_disable_runner_service() {
    local load_state
    load_state=$(systemctl show "$UNIT_NAME" --property=LoadState --value 2>/dev/null) || {
        echo "ERROR: unable to inspect trusted runner service" >&2
        return 1
    }
    if [ "$load_state" = not-found ]; then
        return 0
    fi
    [ "$load_state" = loaded ] || {
        echo "ERROR: trusted runner service load state is invalid" >&2
        return 1
    }
    systemctl stop "$UNIT_NAME" 2>/dev/null || {
        disable_runner_service || \
            echo "ERROR: trusted runner rollback could not prove fail-closed state" >&2
        echo "ERROR: unable to stop trusted runner service" >&2
        return 1
    }
    disable_runner_service || {
        echo "ERROR: unable to disable trusted runner service" >&2
        return 1
    }
}

verify_started_runner_process() {
    local main_pid control_group executable expected_uid expected_gid
    local uid_real uid_effective uid_saved uid_fs
    local gid_real gid_effective gid_saved gid_fs
    main_pid=$(systemctl show "$UNIT_NAME" --property=MainPID --value) \
        || return 1
    [[ "$main_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    control_group=$(systemctl show "$UNIT_NAME" --property=ControlGroup --value) \
        || return 1
    [[ "$control_group" == /* && "$control_group" == */"$UNIT_NAME" ]] \
        || return 1
    [[ "$control_group" != *'..'* && "$control_group" != *'//'* \
        && "$control_group" != *[[:space:]]* ]] || return 1
    executable=$(readlink -f -- "$PROC_ROOT/$main_pid/exe") || return 1
    [ "$executable" = "$RUNNER_DIR/bin/Runner.Listener" ] || return 1
    expected_uid=$(id -u "$RUNNER_USER") || return 1
    expected_gid=$(id -g "$RUNNER_USER") || return 1
    read -r uid_real uid_effective uid_saved uid_fs < <(
        awk '$1 == "Uid:" {print $2, $3, $4, $5}' \
            "$PROC_ROOT/$main_pid/status"
    ) || return 1
    read -r gid_real gid_effective gid_saved gid_fs < <(
        awk '$1 == "Gid:" {print $2, $3, $4, $5}' \
            "$PROC_ROOT/$main_pid/status"
    ) || return 1
    [ "$uid_real" = "$expected_uid" ] \
        && [ "$uid_effective" = "$expected_uid" ] \
        && [ "$uid_saved" = "$expected_uid" ] \
        && [ "$uid_fs" = "$expected_uid" ] \
        && [ "$gid_real" = "$expected_gid" ] \
        && [ "$gid_effective" = "$expected_gid" ] \
        && [ "$gid_saved" = "$expected_gid" ] \
        && [ "$gid_fs" = "$expected_gid" ] \
        && awk -F: -v expected="$control_group" '
            NF != 3 || $3 != expected {exit 1}
            {seen = 1}
            END {if (!seen) exit 1}
        ' "$PROC_ROOT/$main_pid/cgroup"
}

register_and_start() {
    local id token runner runner_id config_status install_payload=false \
        fresh_registration=false pre_registration_empty=false
    [ "$(id -u)" -eq 0 ] || { echo "ERROR: registration requires root" >&2; exit 1; }
    id=$(ensure_group) || exit 1
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
    if [ "$install_payload" = true ]; then
        ensure_runner_payload || {
            echo "ERROR: runner payload provisioning failed" >&2
            exit 1
        }
    fi
    if [ ! -f "$RUNNER_DIR/.runner" ]; then
        group_has_no_runners "$id" || {
            echo "ERROR: trusted runner pre-registration roster is not empty" >&2
            exit 1
        }
        pre_registration_empty=true
        fresh_registration=true
        verify_runner_account || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner account boundary mismatch"
        }
        assert_runner_user_quiescent || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner identity is not quiescent before registration"
        }
        if ! { verify_runner_payload && verify_runner_payload_tree \
            && verify_runner_payload_ownership; }; then
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner executable identity changed before token request"
        fi
        if ! token=$(api --method POST \
            "orgs/$ORG/actions/runners/registration-token" --jq .token); then
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner registration token request failed"
        fi
        [ -n "$token" ] || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "empty runner registration token"
        }
        if ! { verify_runner_payload && verify_runner_payload_tree \
            && verify_runner_payload_ownership \
            && assert_runner_user_quiescent; }; then
            token=REDACTED
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner executable identity changed before configuration"
        fi
        open_registration_directory || {
            token=REDACTED
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner registration directory could not be opened safely"
        }
        set +e
        ACTIONS_RUNNER_INPUT_TOKEN="$token" \
            sudo --preserve-env=ACTIONS_RUNNER_INPUT_TOKEN -u "$RUNNER_USER" \
            "$RUNNER_DIR/config.sh" --unattended \
            --url "https://github.com/$ORG" \
            --runnergroup "$GROUP_NAME" --name "$RUNNER_NAME" \
            --labels "$RUNNER_LABEL" --work _work --disableupdate
        config_status=$?
        set -e
        token=REDACTED
        seal_registration_directory || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner registration directory could not be resealed"
        }
        [ "$config_status" -eq 0 ] || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner configuration failed"
        }
        assert_runner_user_quiescent || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner identity remained active after configuration"
        }
        lock_registration_identity_files || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner identity files could not be locked"
        }
        runner=$(wait_for_exact_runner "$id" registered) || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner registration did not reach the exact trusted group"
        }
        runner_id=$(jq -r .id <<<"$runner")
        verify_local_registration_core "$runner_id" "$id" || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "local runner registration mismatch"
        }
        write_registration_identity_seal "$runner_id" "$id" || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "runner identity seal failed"
        }
        verify_local_registration "$runner_id" "$id" || {
            abort_runner_transaction "$id" "$fresh_registration" \
                "$pre_registration_empty" "$runner_id" \
                "local runner registration mismatch"
        }
    fi
    harden_runner_payload || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "runner payload hardening failed"
    }
    install -o root -g root -m 0644 \
        "$TRUSTED_BOOTSTRAP_ROOT/dev-tools/systemd/$UNIT_NAME" \
        "/etc/systemd/system/$UNIT_NAME" || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "trusted runner unit installation failed"
    }
    systemctl daemon-reload || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "trusted runner service reload failed"
    }
    verify_runner_account || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "runner account boundary changed before service start"
    }
    assert_runner_user_quiescent || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "runner identity is not quiescent before service start"
    }
    systemctl enable --now "$UNIT_NAME" || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "trusted runner service start failed"
    }
    systemctl is-active --quiet "$UNIT_NAME" || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "trusted runner service is not active"
    }
    verify_started_runner_process || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "started runner process/cgroup identity mismatch"
    }
    runner=$(wait_for_exact_runner "$id" online "$runner_id") || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "trusted runner did not become online and idle"
    }
    verify_local_registration "$(jq -r .id <<<"$runner")" "$id" || {
        abort_runner_transaction "$id" "$fresh_registration" \
            "$pre_registration_empty" "$runner_id" \
            "local runner identity changed after start"
    }
}

case "$BOOTSTRAP_PHASE" in
    loader)
        materialize_trusted_main_bootstrap || exit 1
        exec /usr/bin/env \
            TALO_TRUSTED_BOOTSTRAP_PHASE=sealed-worker \
            TALO_TRUSTED_BOOTSTRAP_ROOT="$TRUSTED_BOOTSTRAP_ROOT" \
            TALO_TRUSTED_SOURCE_ROOT="$TRUSTED_SOURCE_ROOT" \
            TALO_TRUSTED_MAIN_COMMIT="$TRUSTED_MAIN_COMMIT" \
            "$TRUSTED_BOOTSTRAP_ROOT/dev-tools/provision-talo-0001-trusted-runner.sh" \
            "$MODE"
        ;;
    sealed-worker)
        validate_sealed_bootstrap || exit 1
        ;;
    *)
        echo "ERROR: unknown trusted bootstrap phase" >&2
        exit 1
        ;;
esac

case "$MODE" in
    --ensure-group) ensure_group >/dev/null ;;
    --verify-group)
        current_group_id=$(group_id)
        [[ "$current_group_id" =~ ^[1-9][0-9]*$ ]] || {
            echo "ERROR: trusted runner group missing or duplicated" >&2
            exit 1
        }
        verify_group "$current_group_id"
        ;;
    --register-and-start) register_and_start ;;
esac
