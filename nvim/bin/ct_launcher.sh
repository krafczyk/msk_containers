#!/usr/bin/env bash

# Resolve a compatibility launcher from a complete package bin directory. The
# sole argument is a ct_*.sh basename. The function prints the executable path,
# returns 2 for an invalid basename, and returns 1 for an incomplete package.
# It has no filesystem side effects.
ct_launcher_path() {
  local entrypoint=${1:-} root launcher helper required

  if [[ $# -ne 1 || $entrypoint != ct_*.sh || $entrypoint == */* ]]; then
    printf 'ct launcher: invalid container tool entrypoint: %s\n' "$entrypoint" >&2
    return 2
  fi

  if [[ -z ${CT_ROOT:-} ]]; then
    helper=${BASH_SOURCE[0]}
    [[ -f $helper ]] || {
      printf 'ct launcher: cannot resolve co-located launcher directory\n' >&2
      return 1
    }
    root=$(dirname -- "$helper") || return 1
  else
    [[ $CT_ROOT == /* ]] || {
      printf 'ct launcher: CT_ROOT must be an absolute path\n' >&2
      return 1
    }
    if ! root=$(realpath -e -- "$CT_ROOT" 2>/dev/null) || [[ ! -d $root ]]; then
      printf 'ct launcher: CT_ROOT is not an existing directory: %s\n' "$CT_ROOT" >&2
      return 1
    fi
  fi

  for required in container-tools ct_exec.sh ct_shell.sh ct_instance_exec.sh ct_mount_detector.sh ct_args.sh; do
    [[ -f $root/$required && -x $root/$required ]] || {
      printf 'ct launcher: CT_ROOT is not a complete container-tools package bin directory: %s\n' "$root" >&2
      return 1
    }
  done

  launcher="$root/$entrypoint"
  [[ -f $launcher && -x $launcher ]] || {
    printf 'ct launcher: container tool launcher is not a regular executable: %s\n' "$launcher" >&2
    return 1
  }
  printf '%s\n' "$launcher"
}
