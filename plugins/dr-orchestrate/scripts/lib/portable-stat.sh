#!/usr/bin/env bash
# shellcheck shell=bash

portable_mode() {
  local path="$1" value
  if value="$(stat -c %a -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "${value: -3}"
    return 0
  fi
  if value="$(stat -f %Lp -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "${value: -3}"
    return 0
  fi
  return 1
}

portable_mtime() {
  local path="$1" value
  if value="$(stat -c %Y -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if value="$(stat -f %m -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

portable_uid() {
  local path="$1" value
  if value="$(stat -c %u -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if value="$(stat -f %u -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

portable_size() {
  local path="$1" value
  if value="$(stat -Lc %s -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if value="$(stat -Lf %z -- "$path" 2>/dev/null)" && [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}

portable_identity() {
  local path="$1" value
  if value="$(stat -Lc '%d:%i' -- "$path" 2>/dev/null)" \
    && [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if value="$(stat -Lf '%d:%i' -- "$path" 2>/dev/null)" \
    && [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  return 1
}
