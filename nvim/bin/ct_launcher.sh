#!/usr/bin/env bash

# Resolve a container-tool launcher from CT_ROOT or the installed launcher
# directory. The sole argument is a ct_*.sh basename. The function prints the
# executable path beneath the canonical root, returns 2 for an invalid basename,
# and returns 1 when the root or executable is unusable. It has no filesystem
# side effects.
ct_launcher_path() {
  local entrypoint=${1:-} root launcher helper

  if [[ $# -ne 1 || $entrypoint != ct_*.sh || $entrypoint == */* ]]; then
    printf 'ct launcher: invalid container tool entrypoint: %s\n' "$entrypoint" >&2
    return 2
  fi

  if [[ -z ${CT_ROOT:-} ]]; then
    helper=$(realpath -e -- "${BASH_SOURCE[0]}" 2>/dev/null) || {
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

  launcher="$root/$entrypoint"
  [[ -f $launcher && -x $launcher ]] || {
    printf 'ct launcher: container tool launcher is not a regular executable: %s\n' "$launcher" >&2
    return 1
  }
  printf '%s\n' "$launcher"
}
