#!/usr/bin/env bash
# shellcheck shell=bash
# Private-state primitives for context-window self-clearing.

ctx_state_root() {
  printf '%s\n' "${DR_ORCH_CONTEXT_STATE:-${DR_ORCH_STATE_DIR:-$HOME/.local/share/datarim-orchestrate/state}/context-window}"
}

ctx_state_init() {
  local root
  root="$(ctx_state_root)"
  umask 077
  mkdir -p "$root" "$root/instances" "$root/transactions" "$root/events" "$root/config" "$root/active" "$root/audit" "$root/replacements"
  chmod 700 "$root" "$root/instances" "$root/transactions" "$root/events" "$root/config" "$root/active" "$root/audit" "$root/replacements"
}

ctx_current_uid() { id -u; }

ctx_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}

ctx_uid() {
  if stat -c '%u' "$1" >/dev/null 2>&1; then stat -c '%u' "$1"; else stat -f '%u' "$1"; fi
}

ctx_nlink() {
  if stat -c '%h' "$1" >/dev/null 2>&1; then stat -c '%h' "$1"; else stat -f '%l' "$1"; fi
}

ctx_identity() {
  case "$1" in /proc/self/fd/*|/dev/fd/*) stat -Lc '%d:%i' "$1" 2>/dev/null || stat -Lf '%d:%i' "$1" ;; *)
    if stat -c '%d:%i' "$1" >/dev/null 2>&1; then stat -c '%d:%i' "$1"; else stat -f '%d:%i' "$1"; fi ;;
  esac
}

ctx_secure_regular() {
  local path="$1" expected_mode="${2:-600}"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  [ "$(ctx_uid "$path")" = "$(ctx_current_uid)" ] || return 1
  [ "$(ctx_nlink "$path")" = 1 ] || return 1
  [ "$(ctx_mode "$path")" = "$expected_mode" ]
}

ctx_secure_owner_regular() {
  local path="$1" mode group_digit other_digit
  [ -f "$path" ] && [ ! -L "$path" ] && [ "$(ctx_uid "$path")" = "$(ctx_current_uid)" ] && [ "$(ctx_nlink "$path")" = 1 ] || return 1
  mode="$(ctx_mode "$path")"; group_digit="${mode: -2:1}"; other_digit="${mode: -1}"
  case "$group_digit$other_digit" in *[2367]*) return 1 ;; esac
}

ctx_secure_parent() {
  local path="$1" root="${DR_ORCH_CONTEXT_TRUST_ROOT:-$HOME}" current mode group_digit other_digit
  case "$path" in "$root"|"$root"/*) ;; *) return 1 ;; esac
  current="$(dirname "$path")"
  while [ "$current" != "$root" ]; do
    [ -d "$current" ] && [ ! -L "$current" ] || return 1
    [ "$(ctx_uid "$current")" = "$(ctx_current_uid)" ] || return 1
    mode="$(ctx_mode "$current")"
    group_digit="${mode: -2:1}"; other_digit="${mode: -1}"
    case "$group_digit$other_digit" in *[2367]*) return 1 ;; esac
    current="$(dirname "$current")"
  done
  [ -d "$root" ] && [ ! -L "$root" ] && [ "$(ctx_uid "$root")" = "$(ctx_current_uid)" ] || return 1
  mode="$(ctx_mode "$root")"; group_digit="${mode: -2:1}"; other_digit="${mode: -1}"
  case "$group_digit$other_digit" in *[2367]*) return 1 ;; esac
}

ctx_sha256() {
  local path="$1" before after fd_path digest
  [ -f "$path" ] && [ ! -L "$path" ] || return 1; before="$(ctx_identity "$path")"; exec {hash_fd}<"$path"
  fd_path="/proc/self/fd/$hash_fd"; [ -e "$fd_path" ] || fd_path="/dev/fd/$hash_fd"
  [ "$(ctx_identity "$fd_path")" = "$before" ] || { exec {hash_fd}<&-; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then digest="$(sha256sum "$fd_path" | awk '{print $1}')"; else digest="$(shasum -a 256 "$fd_path" | awk '{print $1}')"; fi
  after="$(ctx_identity "$path")"; exec {hash_fd}<&-; [ "$after" = "$before" ] || return 1; printf '%s\n' "$digest"
}

ctx_codex_profile_digest() {
  local path="$1" prefix
  ctx_secure_regular "$path" 600 || return 1; prefix="$(mktemp)"
  [ "$(grep -c '^# DATARIM_MANAGED_END$' "$path")" -eq 1 ] || { rm -f "$prefix"; return 1; }
  awk '/^# DATARIM_MANAGED_END$/ || /^\[projects\./ || /^\[tui\./ || /^\[hooks\.state\./ {exit} {print}' "$path" >"$prefix" || { rm -f "$prefix"; return 1; }
  ctx_sha256 "$prefix"; rm -f "$prefix"
}

ctx_random_hex() { openssl rand -hex "${1:-16}"; }

# The caller holds the store-specific lock. A persisted ordinal gives an exact
# insertion order even when several records are created within one wall-clock
# second.
ctx_next_sequence() {
  local file="$1" current=0 tmp
  if [ -e "$file" ]; then
    ctx_secure_regular "$file" 600 || return 1
    current="$(cat "$file")"
    [[ "$current" =~ ^[0-9]+$ ]] || return 1
  fi
  current=$((current + 1)); tmp="$(mktemp)"; printf '%s\n' "$current" >"$tmp"
  ctx_atomic_publish "$tmp" "$file" 600 || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"; printf '%s\n' "$current"
}

ctx_atomic_publish() {
  local src="$1" dest="$2" mode="${3:-600}" parent tmp
  parent="$(dirname "$dest")"
  ctx_secure_parent "$dest" || return 1
  [ ! -L "$dest" ] || return 1
  if [ -e "$dest" ]; then ctx_secure_regular "$dest" "$mode" || return 1; fi
  tmp="$parent/.ctx.$$.${RANDOM}"
  umask 077
  cp "$src" "$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp"
  ctx_secure_parent "$dest" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$dest"
}

ctx_hmac() {
  local key_file="$1" data_file="$2"
  ctx_secure_regular "$key_file" 600 || return 1
  ctx_secure_regular "$data_file" 600 || return 1
  perl -MDigest::SHA=hmac_sha256_hex -MFcntl=:DEFAULT -e '
    my ($key_path,$data_path)=@ARGV;
    sysopen(my $key,$key_path,O_RDONLY|O_NOFOLLOW) or exit 2;
    sysopen(my $data,$data_path,O_RDONLY|O_NOFOLLOW) or exit 2;
    my @kl=lstat($key_path); my @kf=stat($key); my @dl=lstat($data_path); my @df=stat($data);
    exit 2 unless @kl && @kf && @dl && @df && $kl[0]==$kf[0] && $kl[1]==$kf[1] && $dl[0]==$df[0] && $dl[1]==$df[1] && $kf[3]==1 && $df[3]==1;
    local $/; my $k=<$key>; my $d=<$data>; $k =~ s/\s+\z//;
    print hmac_sha256_hex($d,$k),"\n";
  ' "$key_file" "$data_file"
}


ctx_terminal_state() { case "$1" in completed|aborted) return 0 ;; *) return 1 ;; esac; }

ctx_process_birth() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  if [ -r "/proc/$pid/stat" ]; then awk '{print $22}' "/proc/$pid/stat"; return; fi
  ps -p "$pid" -o lstart= 2>/dev/null | shasum -a 256 | awk 'NF{print $1}'
}

ctx_process_live() {
  local pid="$1" state
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  if [ -r "/proc/$pid/stat" ]; then
    state="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
  else
    state="$(ps -p "$pid" -o stat= 2>/dev/null | awk 'NR==1{print substr($1,1,1)}')"
  fi
  case "$state" in Z|X|'') return 1 ;; *) kill -0 "$pid" 2>/dev/null ;; esac
}

ctx_path_identity() {
  perl -e '
    my @s = lstat($ARGV[0]);
    exit 1 unless @s;
    print "$s[0]:$s[1]\n";
  ' "$1"
}

ctx_lock_reclaim_stale_owner() {
  local lock="$1" expected_identity="$2" expected_pid="$3" expected_birth="$4"
  local owner="$lock/owner" claim="$lock/.reclaim" identity pid birth current stale

  mkdir "$claim" 2>/dev/null || return 1
  identity="$(ctx_path_identity "$lock" 2>/dev/null || true)"
  if [ "$identity" != "$expected_identity" ] || ! ctx_secure_regular "$owner" 600; then
    rmdir "$claim" 2>/dev/null || true
    return 1
  fi
  read -r pid birth <"$owner" || true
  current="$(ctx_process_birth "$pid" 2>/dev/null || true)"
  if [ "$pid" != "$expected_pid" ] || [ "$birth" != "$expected_birth" ] \
    || ! [[ "$pid" =~ ^[0-9]+$ && -n "$birth" ]] \
    || { [ "$current" = "$birth" ] && ctx_process_live "$pid"; }; then
    rmdir "$claim" 2>/dev/null || true
    return 1
  fi

  stale="${lock}.stale.$$.$RANDOM"
  if ! mv "$lock" "$stale" 2>/dev/null; then
    rmdir "$claim" 2>/dev/null || true
    return 1
  fi
  rm -f "$stale/owner"
  rmdir "$stale/.reclaim" "$stale" 2>/dev/null || return 1
}

ctx_lock_acquire() {
  local lock="$1" tries=0 owner pid birth current identity
  owner="$lock/owner"
  while ! mkdir "$lock" 2>/dev/null; do
    identity="$(ctx_path_identity "$lock" 2>/dev/null || true)"
    if ctx_secure_regular "$owner" 600; then
      read -r pid birth <"$owner" || true
      current="$(ctx_process_birth "$pid" 2>/dev/null || true)"
      if [[ "$pid" =~ ^[0-9]+$ && -n "$birth" ]] && { [ "$current" != "$birth" ] || ! ctx_process_live "$pid"; }; then
        ctx_lock_reclaim_stale_owner "$lock" "$identity" "$pid" "$birth" && continue
      fi
    fi
    tries=$((tries + 1)); [ "$tries" -lt 300 ] || return 1
    sleep 0.01
  done
  printf '%s %s\n' "$$" "$(ctx_process_birth "$$")" >"$owner"; chmod 600 "$owner"
}

ctx_lock_release() { rm -f "$1/owner"; rmdir "$1" 2>/dev/null || true; }

ctx_instance_safe() { [[ "$1" =~ ^[a-f0-9]{32}$ ]]; }
ctx_incarnation_safe() { [[ "$1" =~ ^[a-f0-9]{32}$ ]]; }
ctx_pane_safe() { [[ "$1" =~ ^[%A-Za-z0-9_.:-]{1,128}$ ]]; }
