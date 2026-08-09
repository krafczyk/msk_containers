#!/usr/bin/env bash
# Resolve a verified host package, or build one private dynamic bootstrap package.
set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
repo=$(realpath "$script_dir/../..")
bootstrap_base=/tmp/mkchad-v1/container-tools-c11
bootstrap_default_root=$bootstrap_base/bootstrap

require_timeout() {
  local timeout_version

  timeout_command=$(command -v timeout) || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: timeout' >&2
    exit 69
  }
  timeout_version=$("$timeout_command" --version 2>&1) || {
    printf '%s\n' 'container-tools bootstrap requires GNU timeout' >&2
    exit 69
  }
  [[ $timeout_version == *'GNU coreutils'* ]] || {
    printf '%s\n' 'container-tools bootstrap requires GNU timeout' >&2
    exit 69
  }
}

complete_package() {
  local executable=$1

  [[ -f $executable && -x $executable ]] &&
    "$timeout_command" --kill-after=5 30 "$executable" package verify >/dev/null 2>&1
}

matching_bootstrap_package() {
  local executable=$1 architecture=$2 commit=$3 metadata status

  [[ -f $executable && -x $executable ]] || return 1
  metadata=$("$timeout_command" --kill-after=5 30 "$executable" package verify --json 2>/dev/null)
  status=$?
  (( status == 0 )) || return "$status"
  [[ $metadata == *"\"architecture\":\"$architecture\""* &&
     $metadata == *"\"source_commit\":\"$commit\""* ]]
}

fail_package() {
  local source=$1 path=$2

  printf 'container-tools %s package is not complete: %s\n' "$source" "$path" >&2
  exit 1
}

require_bootstrap_source() {
  local gitlink source_top source_head source_status

  git_command=$(command -v git) || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: git' >&2
    exit 69
  }
  gitlink=$("$timeout_command" --kill-after=5 30 "$git_command" -C "$repo" ls-tree HEAD -- container_tools)
  gitlink=${gitlink%$'\t'container_tools}
  [[ $gitlink =~ ^160000\ commit\ ([0-9a-f]{40})$ ]] || {
    printf '%s\n' 'container-tools bootstrap requires a container_tools gitlink' >&2
    exit 78
  }
  source_commit=${BASH_REMATCH[1]}
  source_root=$(realpath -e "$repo/container_tools" 2>/dev/null) || {
    printf '%s\n' 'container-tools bootstrap source is unavailable' >&2
    exit 78
  }
  source_top=$("$timeout_command" --kill-after=5 30 "$git_command" -C "$source_root" rev-parse --show-toplevel 2>/dev/null)
  source_top=$(realpath -e "$source_top")
  [[ $source_top == "$source_root" ]] || {
    printf '%s\n' 'container-tools bootstrap source must be its Git top-level' >&2
    exit 78
  }
  source_head=$("$timeout_command" --kill-after=5 30 "$git_command" -C "$source_root" rev-parse HEAD)
  source_status=$("$timeout_command" --kill-after=5 60 "$git_command" -C "$source_root" status --porcelain)
  [[ $source_head == "$source_commit" && -z $source_status ]] || {
    printf '%s\n' 'container-tools bootstrap source must be clean at the parent gitlink commit' >&2
    exit 78
  }
}

resolve_bootstrap_root() {
  local override=${CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT:-}

  if [[ -n $override ]]; then
    [[ $override == /* ]] || {
      printf '%s\n' 'container-tools bootstrap test root must be absolute' >&2
      exit 64
    }
    bootstrap_root=$(realpath -m -- "$override")
    case $bootstrap_root in
      "$bootstrap_base"/*) ;;
      *)
        printf 'container-tools bootstrap test root must be beneath %s\n' "$bootstrap_base" >&2
        exit 64
        ;;
    esac
  else
    bootstrap_root=$bootstrap_default_root
  fi
}

native_architecture() {
  local machine

  uname_command=$(command -v uname) || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: uname' >&2
    exit 69
  }
  machine=$("$timeout_command" --kill-after=5 15 "$uname_command" -m) || {
    printf '%s\n' 'container-tools bootstrap could not determine the native architecture' >&2
    exit 69
  }
  case $machine in
    x86_64 | amd64) printf '%s\n' x86_64 ;;
    aarch64 | arm64) printf '%s\n' aarch64 ;;
    ppc64le) printf '%s\n' ppc64le ;;
    *)
      printf 'container-tools bootstrap does not support native architecture: %s\n' "$machine" >&2
      exit 64
      ;;
  esac
}

remove_stale_stages() {
  local -a stale_stages

  shopt -s nullglob
  stale_stages=("$architecture_root"/.source-"$source_commit".* "$architecture_root"/.next-"$source_commit".*)
  shopt -u nullglob
  (( ${#stale_stages[@]} == 0 )) || rm -rf -- "${stale_stages[@]}"
}

cache_validation_failed() {
  local status=$1

  [[ $status == 1 || $status == 78 ]]
}

bootstrap_package() {
  local compiler prefix source_stage build_stage next architecture_root status

  require_bootstrap_source
  resolve_bootstrap_root
  native_architecture=$(native_architecture)
  architecture_root="$bootstrap_root/$native_architecture"
  prefix="$architecture_root/$source_commit"
  if matching_bootstrap_package "$prefix/bin/container-tools" "$native_architecture" "$source_commit"; then
    printf '%s\n' "$prefix/bin/container-tools"
    return
  else
    status=$?
  fi
  cache_validation_failed "$status" || return "$status"

  cmake_command=$(command -v cmake) || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: cmake' >&2
    exit 69
  }
  compiler=${CC:-cc}
  command -v "$compiler" >/dev/null 2>&1 || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: C compiler' >&2
    exit 69
  }
  flock_command=$(command -v flock) || {
    printf '%s\n' 'container-tools bootstrap missing prerequisite: flock' >&2
    exit 69
  }

  mkdir -p -- "$architecture_root"
  exec 9>"$architecture_root/.bootstrap.lock"
  "$flock_command" -w 3600 9 || {
    printf '%s\n' 'container-tools bootstrap lock timed out' >&2
    exit 75
  }
  # The clean source can change while waiting; derive all source-keyed paths again.
  require_bootstrap_source
  prefix="$architecture_root/$source_commit"
  if matching_bootstrap_package "$prefix/bin/container-tools" "$native_architecture" "$source_commit"; then
    printf '%s\n' "$prefix/bin/container-tools"
    return
  else
    status=$?
  fi
  cache_validation_failed "$status" || return "$status"
  remove_stale_stages
  rm -rf -- "$prefix"
  source_stage=$(mktemp -d "$architecture_root/.source-${source_commit}.XXXXXX")
  cleanup_bootstrap() {
    [[ -z ${source_stage:-} ]] || rm -rf -- "$source_stage"
    [[ -z ${next:-} ]] || rm -rf -- "$next"
  }
  trap cleanup_bootstrap EXIT ERR
  next=$(mktemp -d "$architecture_root/.next-${source_commit}.XXXXXX")
  "$timeout_command" --kill-after=10 300 "$git_command" clone --no-checkout --no-local "$source_root" "$source_stage" >&2
  "$timeout_command" --kill-after=10 120 "$git_command" -C "$source_stage" checkout --detach "$source_commit" >&2
  [[ $("$timeout_command" --kill-after=5 30 "$git_command" -C "$source_stage" rev-parse HEAD) == "$source_commit" ]] || {
    printf '%s\n' 'container-tools bootstrap private source staging selected the wrong commit' >&2
    exit 78
  }
  build_stage="$source_stage/build"
  "$timeout_command" --kill-after=10 300 "$cmake_command" -S "$source_stage" -B "$build_stage" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$compiler" -DCONTAINER_TOOLS_STATIC=OFF -DBUILD_TESTING=OFF >&2
  "$timeout_command" --kill-after=10 1800 "$cmake_command" --build "$build_stage" >&2
  "$timeout_command" --kill-after=10 300 "$cmake_command" --install "$build_stage" --prefix "$next" >&2
  if matching_bootstrap_package "$next/bin/container-tools" "$native_architecture" "$source_commit"; then
    :
  else
    status=$?
    cache_validation_failed "$status" && {
      printf '%s\n' 'container-tools bootstrap produced a package with the wrong identity' >&2
      return 78
    }
    return "$status"
  fi
  mv -- "$next" "$prefix"
  next=
  rm -rf -- "$source_stage"
  source_stage=
  trap - EXIT ERR
  printf '%s\n' "$prefix/bin/container-tools"
}

require_timeout

if [[ -n ${CT_ROOT:-} ]]; then
  [[ $CT_ROOT == /* ]] || {
    printf '%s\n' 'CT_ROOT must be an absolute package bin directory' >&2
    exit 1
  }
  container_tools=$(realpath -e -- "$CT_ROOT/container-tools" 2>/dev/null) ||
    fail_package CT_ROOT "$CT_ROOT"
  complete_package "$container_tools" || fail_package CT_ROOT "$CT_ROOT"
  printf '%s\n' "$container_tools"
  exit
fi

if container_tools=$(command -v container-tools); then
  container_tools=$(realpath -e -- "$container_tools" 2>/dev/null) ||
    fail_package PATH "$container_tools"
  complete_package "$container_tools" || fail_package PATH "$container_tools"
  printf '%s\n' "$container_tools"
  exit
fi

bootstrap_package
