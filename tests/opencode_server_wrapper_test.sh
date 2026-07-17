#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/opencode-mkchad}
wrapper=${2:?pass the wrapper path}
wrapper=$(realpath "$wrapper")
[[ $work == /tmp/opencode-mkchad/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/opencode-mkchad' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
config="$work/config"
fake="$work/fake-bin"
bin="$home/.local/bin"
image="$work/neovim.sif"
runtime_log="$work/runtime.log"
nvim_log="$work/nvim.log"
installed_wrapper="$bin/mkchad-opencode-server"
installed_image_command="$bin/mkchad-opencode-server-image"
mount_config="$work/ct_mount.conf"
repo=${wrapper%/nvim/bin/mkchad-opencode-server}
installer="$repo/bin/install_nvim.sh"
mkdir -p "$home" "$config/mkchad/lua/mkchad/opencode" "$fake"
: > "$config/mkchad/lua/mkchad/opencode/command.lua"
: > "$image"
: > "$mount_config"
HOME="$home" "$installer" >/dev/null

cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
exit 64
EOF
cat > "$bin/ct_exec.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_RUNTIME_LOG"
printf 'mount_config=%s\n' "${CT_MOUNT_CFG:-}" >> "$MKCHAD_TEST_RUNTIME_LOG"
exit 23
EOF
cat > "$fake/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_NVIM_LOG"
printf 'marker=%s runtime=%s cache=%s npm=%s config=%s\n' "${MKCHAD_NVIM_IMAGE:-}" "${XDG_RUNTIME_DIR:-}" "${XDG_CACHE_HOME:-}" "${MSK_NPM_GLOBAL_BASE:-}" "${OPENCODE_CONFIG:-}" >> "$MKCHAD_TEST_NVIM_LOG"
exit 19
EOF
chmod 755 "$fake/apptainer" "$fake/nvim" "$bin/ct_exec.sh"

base_env=(
  "HOME=$home"
  "XDG_CONFIG_HOME=$config"
  "XDG_RUNTIME_DIR=$home/.local/share/mkchad/tmp"
  "XDG_CACHE_HOME=$home/.local/cache"
  "XDG_DATA_HOME=$home/.local/share"
  "NVIM_CONT_LOCATION=$image"
  "MKCHAD_TEST_RUNTIME_LOG=$runtime_log"
  "MKCHAD_TEST_NVIM_LOG=$nvim_log"
  "CT_MOUNT_CFG=$mount_config"
  "PATH=$fake:$PATH"
)

set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  "$installed_image_command" status --json >"$work/direct-host.out" 2>"$work/direct-host.err"
direct_host_status=$?
set -e
[[ $direct_host_status -ne 0 && $(<"$work/direct-host.err") == *'must run inside the active MkChad image'* ]] || {
  printf '%s\n' 'in-image command did not refuse direct host execution' >&2; exit 1;
}

set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" MKCHAD_NVIM_CONTAINER=1 "$installed_wrapper" status --json
host_status=$?
set -e
[[ $host_status -eq 23 ]] || { printf '%s\n' 'host-supplied legacy marker selected direct nvim' >&2; exit 1; }
mapfile -t runtime_argv < "$runtime_log"
[[ ${runtime_argv[0]} == --apptainer && ${runtime_argv[1]} == --env && ${runtime_argv[2]} == MKCHAD_NVIM_IMAGE=1 ]] || {
  printf '%s\n' 'host invocation did not delegate to the configured container launcher' >&2; exit 1;
}
[[ ${runtime_argv[3]} == --env && ${runtime_argv[4]} == NVIM_APPNAME=mkchad \
  && ${runtime_argv[5]} == --env && ${runtime_argv[6]} == "XDG_CONFIG_HOME=$config" \
  && ${runtime_argv[7]} == --env && ${runtime_argv[8]} == "XDG_RUNTIME_DIR=$home/.local/share/mkchad/tmp" \
  && ${runtime_argv[9]} == --env && ${runtime_argv[10]} == "XDG_CACHE_HOME=$home/.local/cache" \
  && ${runtime_argv[11]} == --env && ${runtime_argv[12]} == MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  && ${runtime_argv[13]} == --env && ${runtime_argv[14]} == "OPENCODE_CONFIG=$config/mkchad/opencode.jsonc" ]] || {
  printf '%s\n' 'host invocation changed the MkChad image environment' >&2; exit 1;
}
[[ ${runtime_argv[15]} == --ct-bind && ${runtime_argv[16]} == "$home/.local/share/msk_containers/npm-global:/opt/msk/npm-global" ]] || {
  printf '%s\n' 'host invocation did not preserve the explicit npm bind' >&2; exit 1;
}
[[ ${runtime_argv[17]} == "$image" && ${runtime_argv[18]} == "$installed_image_command" && ${runtime_argv[19]} == status && ${runtime_argv[20]} == --json ]] || {
  printf '%s\n' 'host invocation changed the image lifecycle entrypoint' >&2; exit 1;
}
[[ ${runtime_argv[21]} == "mount_config=$mount_config" ]] || {
  printf '%s\n' 'host invocation did not preserve container mount configuration' >&2; exit 1;
}
[[ ! -e $nvim_log ]] || { printf '%s\n' 'host invocation ran native nvim' >&2; exit 1; }

rm "$runtime_log"
set +e
env "${base_env[@]}" \
  SINGULARITY_CONTAINER="$image" \
  MKCHAD_NVIM_IMAGE=1 \
  XDG_RUNTIME_DIR="$work/image-runtime" XDG_CACHE_HOME="$work/image-cache" \
  MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global OPENCODE_CONFIG="$config/mkchad/opencode.jsonc" \
  "$installed_image_command" status --json
container_status=$?
set -e
[[ $container_status -eq 19 ]] || { printf '%s\n' 'in-container invocation did not call image nvim directly' >&2; exit 1; }
[[ ! -e $runtime_log ]] || { printf '%s\n' 'in-container invocation nested the container runtime' >&2; exit 1; }
mapfile -t nvim_argv < "$nvim_log"
[[ ${nvim_argv[0]} == -u && ${nvim_argv[1]} == NONE && ${nvim_argv[2]} == -l && ${nvim_argv[4]} == -- && ${nvim_argv[5]} == status && ${nvim_argv[6]} == --json ]] || {
  printf '%s\n' 'in-container nvim argv changed' >&2; exit 1;
}
[[ $(<"$nvim_log") == *"marker=1 runtime=$work/image-runtime cache=$work/image-cache npm=/opt/msk/npm-global config=$config/mkchad/opencode.jsonc"* ]] || {
  printf '%s\n' 'in-container invocation did not preserve MkChad environment' >&2; exit 1;
}

rm "$nvim_log"
set +e
env "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 "$installed_wrapper" status --json
compatibility_status=$?
set -e
[[ $compatibility_status -eq 19 && -e $nvim_log && ! -e $runtime_log ]] || {
  printf '%s\n' 'public launcher did not preserve in-container compatibility without nesting' >&2; exit 1;
}
printf '%s\n' 'opencode server wrapper tests passed'
