#!/usr/bin/env bash

# Launch a payload through the fixed persistent MkChad profile. The first two
# parameters are the selected runtime and image; remaining arguments are the
# payload passed to the bootstrap. Payload command, environment, and working
# directory are deliberately after the profile separator and do not select an
# instance. Returns nonzero before dispatch on invalid host setup; otherwise
# replaces the caller with the persistent container dispatcher.
mkchad_persistent_launcher_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
mkchad_persistent_bootstrap="$mkchad_persistent_launcher_dir/mkchad-container-bootstrap"

mkchad_persistent_exec() {
  local runtime=$1 image=$2
  local payload_cwd=$PWD
  local runtime_dir="$HOME/.local/share/mkchad/tmp"
  local config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
  local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
  local cache_dir=${XDG_CACHE_HOME:-"$HOME/.local/cache"}
  local data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
  local npm_base="$HOME/.local/share/msk_containers/npm-global"
  local npm_container_base=/opt/msk/npm-global
  local opencode_config="$config_home/mkchad/opencode.jsonc"
  local home_real state_real container_launcher
  local state_bind=()

  shift 2

  [[ $state_home == /* ]] || {
    printf 'mkchad persistent launcher: XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
    return 1
  }
  [[ -x $mkchad_persistent_bootstrap ]] || {
    printf 'mkchad persistent launcher: container bootstrap is missing or not executable: %s\n' "$mkchad_persistent_bootstrap" >&2
    return 1
  }

  home_real=$(realpath -m -- "$HOME")
  state_real=$(realpath -m -- "$state_home")
  case "$state_real/" in
    "$home_real/"*) ;;
    *)
      [[ -d $state_home ]] || {
        printf 'mkchad persistent launcher: external XDG_STATE_HOME must be an existing directory for an identical host/image bind: %s\n' "$state_home" >&2
        return 1
      }
      state_bind=(--ct-bind "$state_home:$state_home")
      ;;
  esac

  mkdir -p -- "$runtime_dir" "$cache_dir" "$npm_base"
  cd -- "$HOME" || return 1
  container_launcher=$(ct_launcher_path ct_instance_exec.sh) || return $?
  exec "$container_launcher" "--$runtime" \
    --ct-instance-root "$runtime_dir/container-instances" \
    --ct-bind "$npm_base:$npm_container_base" \
    "${state_bind[@]}" \
    --ct-env "MKCHAD_PERSISTENT_INSTANCE=1" \
    --ct-env "MKCHAD_NVIM_IMAGE=1" \
    --ct-env "NVIM_APPNAME=mkchad" \
    --ct-env "XDG_CONFIG_HOME=$config_home" \
    --ct-env "XDG_STATE_HOME=$state_home" \
    --ct-env "XDG_RUNTIME_DIR=$runtime_dir" \
    --ct-env "XDG_CACHE_HOME=$cache_dir" \
    --ct-env "XDG_DATA_HOME=$data_home" \
    --ct-env "MSK_NPM_GLOBAL_BASE=$npm_container_base" \
    --ct-env "OPENCODE_CONFIG=$opencode_config" \
    --ct-bootstrap "$mkchad_persistent_bootstrap" \
    -- "$image" --mkchad-payload-cwd "$payload_cwd" -- "$@"
}
