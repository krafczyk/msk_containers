#!/usr/bin/env bash
# Install or verify one exact container-tools package beneath ${HOME}/.local.
set -euo pipefail
umask 077

program=${0##*/}
script_dir=$(dirname "$(realpath "$0")")
package_installer="$script_dir/../container_tools/scripts/install-package.sh"
check_only=0
recovery_dir=
archive=
digest=
version=
source_commit=
architecture=
libc=
declare -A seen=()

usage() {
  cat <<EOF
Usage: $program [--check] [--recovery-dir DIR] --container-tools-archive FILE \
  --container-tools-sha256 SHA256 --container-tools-version VERSION \
  --container-tools-source-commit COMMIT --container-tools-architecture ARCH \
  --container-tools-libc musl|glibc

Install a verified container-tools package into ${HOME}/.local. --check is
mutation-free; apply and verify are delegated to the package-owned transaction.
EOF
}

die() {
  printf '%s: %s\n' "$program" "$*" >&2
  exit 1
}

check_safe_directory() {
  local path=$1 label=$2 allow_trusted_root=${3:-0} uid mode
  [[ ! -L $path && -d $path ]] || die "unsafe parent is not a directory: $label"
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
  local path
  check_safe_directory "$HOME" "$HOME" 1
  for path in "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share"; do
    [[ ! -e $path && ! -L $path ]] && continue
    check_safe_directory "$path" "$path"
  done
}

set_once() {
  local key=$1 value=$2
  [[ -z ${seen[$key]:-} ]] || die "duplicate container-tools package field: $key"
  seen[$key]=1
  printf -v "$key" '%s' "$value"
}

while (($#)); do
  case $1 in
    --check) (( check_only == 0 )) || die 'duplicate --check'; check_only=1; shift ;;
    --recovery-dir) (($# >= 2)) || die '--recovery-dir requires a path'; set_once recovery_dir "$2"; shift 2 ;;
    --container-tools-archive) (($# >= 2)) || die '--container-tools-archive requires a path'; set_once archive "$2"; shift 2 ;;
    --container-tools-sha256) (($# >= 2)) || die '--container-tools-sha256 requires a value'; set_once digest "$2"; shift 2 ;;
    --container-tools-version) (($# >= 2)) || die '--container-tools-version requires a value'; set_once version "$2"; shift 2 ;;
    --container-tools-source-commit) (($# >= 2)) || die '--container-tools-source-commit requires a value'; set_once source_commit "$2"; shift 2 ;;
    --container-tools-architecture) (($# >= 2)) || die '--container-tools-architecture requires a value'; set_once architecture "$2"; shift 2 ;;
    --container-tools-libc) (($# >= 2)) || die '--container-tools-libc requires a value'; set_once libc "$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ -z $archive && -z $digest && -z $version && -z $source_commit &&
      -z $architecture && -z $libc ]]; then
  archive=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHIVE:-}
  digest=${CONTAINER_TOOLS_HOST_PACKAGE_SHA256:-}
  version=${CONTAINER_TOOLS_HOST_PACKAGE_VERSION:-}
  source_commit=${CONTAINER_TOOLS_HOST_PACKAGE_SOURCE_COMMIT:-}
  architecture=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHITECTURE:-}
  libc=${CONTAINER_TOOLS_HOST_PACKAGE_LIBC:-}
fi
[[ -x $package_installer && -n $archive && -n $digest && -n $version &&
   -n $source_commit && -n $architecture && -n $libc ]] ||
  die 'complete container-tools package identity is required'
[[ $HOME == /* ]] || die 'HOME must be an absolute path'
case ${MKCHAD_TRUST_GROUP_WRITABLE_ROOTS:-0} in
  0|1) ;;
  *) die 'MKCHAD_TRUST_GROUP_WRITABLE_ROOTS must be 0 or 1' ;;
esac
validate_target_parents

package_args=(--archive "$archive" --sha256 "$digest" --version "$version" \
  --source-commit "$source_commit" --architecture "$architecture" --libc "$libc")
if (( check_only )); then
  [[ -z $recovery_dir ]] || die '--recovery-dir is not valid with --check'
  exec "$package_installer" --check "${package_args[@]}" --prefix "$HOME/.local"
fi
if [[ -z $recovery_dir ]]; then
  recovery_dir="$HOME/.local/.container-tools-recovery"
fi
[[ $recovery_dir == /* ]] || die '--recovery-dir must be absolute'
"$package_installer" --apply "${package_args[@]}" --prefix "$HOME/.local" \
  --recovery-dir "$recovery_dir/container-tools"
exec "$package_installer" --verify "${package_args[@]}" --prefix "$HOME/.local"
