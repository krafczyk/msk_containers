#!/usr/bin/env bash

set -euo pipefail
umask 077

program=${0##*/}
script_dir=$(dirname "$(realpath "$0")")
bin_dir="$script_dir/../nvim/bin"
tools_installer="$script_dir/install_tools.sh"
target_dir="$HOME/.local/bin"
check_only=0
recovery_dir=
stage=
recovery_stage=

usage() {
  cat <<EOF
Usage: $program [--check] [--recovery-dir DIR]

Install MkChad launchers and their container tools. --check validates the
complete installer-owned output set without writing. Replacing an existing
non-compliant file requires a caller-created private recovery directory.
EOF
}

die() {
  printf '%s: %s\n' "$program" "$*" >&2
  exit 1
}

cleanup() {
  [[ -z $stage || ! -e $stage ]] || rm -f -- "$stage"
  [[ -z $recovery_stage || ! -e $recovery_stage ]] || rm -f -- "$recovery_stage"
}
trap cleanup EXIT

check_safe_directory() {
  local path=$1 label=$2 allow_trusted_root=${3:-0} uid mode
  [[ ! -L $path ]] || die "unsafe parent symlink: $label"
  [[ -d $path ]] || die "unsafe parent is not a directory: $label"
  uid=$(stat -Lc '%u' -- "$path") || die "cannot inspect parent: $label"
  mode=$(stat -Lc '%a' -- "$path") || die "cannot inspect parent mode: $label"
  if (( allow_trusted_root )) && [[ ${MKCHAD_TRUST_GROUP_WRITABLE_ROOTS:-0} == 1 ]]; then
    [[ $uid == 0 || $uid == "$EUID" ]] || die "unsafe parent is not root- or current-user-owned: $label"
    (( (8#$mode & 002) == 0 )) || die "unsafe parent is group- or world-writable: $label"
    return
  fi
  [[ $uid == "$EUID" ]] || die "unsafe parent is not current-user-owned: $label"
  (( (8#$mode & 022) == 0 )) || die "unsafe parent is group- or world-writable: $label"
}

validate_target_parents() {
  local current=$HOME part
  [[ $HOME == /* ]] || die "HOME must be an absolute path"
  check_safe_directory "$current" "$current" 1
  for part in .local bin; do
    current="$current/$part"
    [[ ! -e $current && ! -L $current ]] && continue
    check_safe_directory "$current" "$current"
  done
}

ensure_target_dir() {
  local current=$HOME part
  validate_target_parents
  for part in .local bin; do
    current="$current/$part"
    if [[ ! -e $current && ! -L $current ]]; then
      mkdir -m 700 -- "$current"
    fi
    check_safe_directory "$current" "$current"
  done
}

validate_recovery_dir() {
  local mode
  [[ -n $recovery_dir ]] || die "a private --recovery-dir is required before replacing existing files"
  [[ ! -L $recovery_dir && -d $recovery_dir ]] || die "recovery directory is not a directory: $recovery_dir"
  check_safe_directory "$recovery_dir" "$recovery_dir"
  mode=$(stat -Lc '%a' -- "$recovery_dir") || die "cannot inspect recovery directory mode: $recovery_dir"
  [[ $mode == 700 ]] || die "recovery directory must have mode 0700: $recovery_dir"
}

validate_source() {
  local source=$1
  [[ ! -L $source && -f $source ]] || die "source is not a regular file: $source"
}

validate_output() {
  local output=$1 uid
  [[ ! -L $output ]] || die "symlink output is unsafe: $output"
  [[ ! -e $output ]] && return
  [[ -f $output ]] || die "non-regular output is unsafe: $output"
  uid=$(stat -Lc '%u' -- "$output") || die "cannot inspect output: $output"
  [[ $uid == "$EUID" ]] || die "foreign-owned output is unsafe: $output"
}

output_is_compliant() {
  local source=$1 output=$2 mode
  validate_output "$output"
  [[ -f $output ]] || return 1
  mode=$(stat -Lc '%a' -- "$output") || die "cannot inspect output mode: $output"
  [[ $mode == 755 ]] && cmp -s -- "$source" "$output"
}

output_identity() {
  local output=$1
  if [[ ! -e $output && ! -L $output ]]; then
    printf '%s\n' absent
    return
  fi
  validate_output "$output"
  stat -Lc '%d:%i' -- "$output" || die "cannot inspect output identity: $output"
}

files=(
  "$bin_dir"/*.sh
  "$bin_dir/nvim"
  "$bin_dir/nvim_shell"
  "$bin_dir/nvim_clear_data"
  "$bin_dir/nvim_clear_npm_global"
  "$bin_dir/mkchad"
  "$bin_dir/mkchad-container-bootstrap"
  "$bin_dir/mkchad-status-host-evidence"
  "$bin_dir/mkchad-opencode-server-image"
  "$bin_dir/mkchad-opencode-server"
  "$bin_dir/install_nvim_container"
)

preflight_launchers() {
  local source output needs_recovery=0
  validate_target_parents
  for source in "${files[@]}"; do
    validate_source "$source"
    output="$target_dir/${source##*/}"
    validate_output "$output"
    if [[ -f $output ]] && ! output_is_compliant "$source" "$output"; then
      needs_recovery=1
    fi
  done
  if (( ! check_only && needs_recovery )) || [[ -n $recovery_dir ]]; then
    validate_recovery_dir
  fi
}

preflight_all() {
  local -a args=(--check)
  [[ -z $recovery_dir ]] || args+=(--recovery-dir "$recovery_dir")
  "$tools_installer" "${args[@]}"
  preflight_launchers
}

backup_output() {
  local output=$1 name=${1##*/} backup
  [[ -f $output ]] || return 0
  validate_recovery_dir
  backup="$recovery_dir/$name"
  [[ ! -e $backup && ! -L $backup ]] || die "recovery asset already exists: $backup"
  recovery_stage=$(mktemp "$recovery_dir/.${name}.XXXXXX")
  cp -- "$output" "$recovery_stage"
  chmod 600 -- "$recovery_stage"
  sync -- "$recovery_stage"
  mv -T -- "$recovery_stage" "$backup"
  recovery_stage=
  sync -- "$recovery_dir"
}

install_file() {
  local source=$1 output="$target_dir/${1##*/}" expected_output_identity target_identity
  output_is_compliant "$source" "$output" && return
  check_safe_directory "$target_dir" "$target_dir"
  target_identity=$(stat -Lc '%d:%i' -- "$target_dir") || die "cannot inspect target directory: $target_dir"
  expected_output_identity=$(output_identity "$output")
  backup_output "$output"
  stage=$(mktemp "$target_dir/.${source##*/}.XXXXXX")
  cp -- "$source" "$stage"
  chmod 755 -- "$stage"
  cmp -s -- "$source" "$stage" || die "staged file does not match source: $source"
  sync -- "$stage"
  [[ $(stat -Lc '%d:%i' -- "$target_dir") == "$target_identity" ]] || die "target directory changed during installation: $target_dir"
  [[ $(output_identity "$output") == "$expected_output_identity" ]] || die "output changed during installation: $output"
  mv -fT -- "$stage" "$output"
  stage=
  sync -- "$output"
  sync -- "$target_dir"
  # This test-only pause lets the interruption fixture stop between replacements.
  [[ ${MSK_INSTALL_TEST_PAUSE_AFTER_REPLACE:-} != "${source##*/}" ]] || sleep 30
}

acquire_lock() {
  local lock="$target_dir/.install_nvim.lock" uid
  [[ ! -L $lock ]] || die "unsafe installer lock symlink: $lock"
  if [[ -e $lock ]]; then
    [[ -f $lock ]] || die "unsafe installer lock type: $lock"
    uid=$(stat -Lc '%u' -- "$lock") || die "cannot inspect installer lock: $lock"
    [[ $uid == "$EUID" ]] || die "foreign-owned installer lock: $lock"
  fi
  exec 9>>"$lock"
  flock -x 9
}

while (($#)); do
  case "$1" in
    --check) check_only=1; shift ;;
    --recovery-dir)
      (($# >= 2)) || die "--recovery-dir requires a path"
      recovery_dir=$2
      shift 2
      ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case ${MKCHAD_TRUST_GROUP_WRITABLE_ROOTS:-0} in
  0 | 1) ;;
  *) die "MKCHAD_TRUST_GROUP_WRITABLE_ROOTS must be 0 or 1" ;;
esac

preflight_all
(( check_only )) && exit 0
ensure_target_dir
acquire_lock
preflight_all
tool_args=(--lock-held)
[[ -z $recovery_dir ]] || tool_args+=(--recovery-dir "$recovery_dir")
"$tools_installer" "${tool_args[@]}"
for source in "${files[@]}"; do
  install_file "$source"
done
