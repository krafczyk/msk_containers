#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/opencode-mkchad}
wrapper=${2:?pass the wrapper path}
[[ $work == /tmp/opencode-mkchad/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/opencode-mkchad' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
config="$work/config"
fake="$work/fake-bin"
image="$work/neovim.sif"
runtime_log="$work/runtime.log"
nvim_log="$work/nvim.log"
mkdir -p "$home" "$config/mkchad/lua/mkchad/opencode" "$fake"
: > "$config/mkchad/lua/mkchad/opencode/command.lua"
: > "$image"

cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_RUNTIME_LOG"
printf 'marker=%s runtime=%s cache=%s npm=%s config=%s\n' "${MKCHAD_NVIM_IMAGE:-}" "${XDG_RUNTIME_DIR:-}" "${XDG_CACHE_HOME:-}" "${MSK_NPM_GLOBAL_BASE:-}" "${OPENCODE_CONFIG:-}" >> "$MKCHAD_TEST_RUNTIME_LOG"
exit 23
EOF
cat > "$fake/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_NVIM_LOG"
printf 'marker=%s runtime=%s cache=%s npm=%s config=%s\n' "${MKCHAD_NVIM_IMAGE:-}" "${XDG_RUNTIME_DIR:-}" "${XDG_CACHE_HOME:-}" "${MSK_NPM_GLOBAL_BASE:-}" "${OPENCODE_CONFIG:-}" >> "$MKCHAD_TEST_NVIM_LOG"
exit 19
EOF
chmod 755 "$fake/apptainer" "$fake/nvim"

base_env=(
  "HOME=$home"
  "XDG_CONFIG_HOME=$config"
  "NVIM_CONT_LOCATION=$image"
  "MKCHAD_TEST_RUNTIME_LOG=$runtime_log"
  "MKCHAD_TEST_NVIM_LOG=$nvim_log"
  "PATH=$fake:$PATH"
)

set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" MKCHAD_NVIM_CONTAINER=1 "$wrapper" status --json
host_status=$?
set -e
[[ $host_status -eq 23 ]] || { printf '%s\n' 'host-supplied legacy marker selected direct nvim' >&2; exit 1; }
mapfile -t runtime_argv < "$runtime_log"
[[ ${runtime_argv[0]} == exec && ${runtime_argv[1]} == --env && ${runtime_argv[2]} == MKCHAD_NVIM_IMAGE=1 ]] || {
  printf '%s\n' 'host invocation did not enter the image exactly once with its marker' >&2; exit 1;
}
[[ ! -e $nvim_log ]] || { printf '%s\n' 'host invocation ran native nvim' >&2; exit 1; }

rm "$runtime_log"
set +e
env "${base_env[@]}" \
  SINGULARITY_CONTAINER="$image" \
  XDG_RUNTIME_DIR="$work/image-runtime" XDG_CACHE_HOME="$work/image-cache" \
  MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global OPENCODE_CONFIG="$config/mkchad/opencode.jsonc" \
  "$wrapper" status --json
container_status=$?
set -e
[[ $container_status -eq 19 ]] || { printf '%s\n' 'in-container invocation did not call image nvim directly' >&2; exit 1; }
[[ ! -e $runtime_log ]] || { printf '%s\n' 'in-container invocation nested the container runtime' >&2; exit 1; }
mapfile -t nvim_argv < "$nvim_log"
[[ ${nvim_argv[0]} == -u && ${nvim_argv[1]} == NONE && ${nvim_argv[2]} == -l && ${nvim_argv[4]} == -- && ${nvim_argv[5]} == status && ${nvim_argv[6]} == --json ]] || {
  printf '%s\n' 'in-container nvim argv changed' >&2; exit 1;
}
[[ $(<"$nvim_log") == *"marker= runtime=$work/image-runtime cache=$work/image-cache npm=/opt/msk/npm-global config=$config/mkchad/opencode.jsonc"* ]] || {
  printf '%s\n' 'in-container invocation did not preserve MkChad environment' >&2; exit 1;
}
printf '%s\n' 'opencode server wrapper tests passed'
