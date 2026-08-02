#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/opencode-mkchad}
wrapper=${2:?pass the nvim_shell path}
wrapper=$(realpath "$wrapper")
[[ $work == /tmp/opencode-mkchad/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/opencode-mkchad' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
fake="$work/fake-bin"
bin="$home/.local/bin"
image="$work/neovim.sif"
runtime_log="$work/runtime.log"
npm_base="$home/.local/share/msk_containers/npm-global"
repo=${wrapper%/nvim/bin/nvim_shell}
installer="$repo/bin/install_nvim.sh"
mkdir -p "$home" "$fake"
: > "$image"
HOME="$home" "$installer" >/dev/null
cmp "$repo/container_tools/ct_library.sh" "$bin/ct_library.sh"
cmp "$repo/container_tools/ct_exec.sh" "$bin/ct_exec.sh"
cmp "$repo/container_tools/ct_shell.sh" "$bin/ct_shell.sh"

cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
exit 64
EOF
cat > "$fake/node" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -p ]] || exit 64
[[ ${2:-} == "process.platform + '-' + process.arch + '-node' + process.versions.node.split('.')[0]" ]] || exit 64
printf '%s-%s-node%s\n' \
  "${MKCHAD_TEST_NODE_PLATFORM:?}" \
  "${MKCHAD_TEST_NODE_ARCH:?}" \
  "${MKCHAD_TEST_NODE_VERSION%%.*}"
EOF
cat > "$bin/ct_shell.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_RUNTIME_LOG"
exit 23
EOF
cat > "$fake/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'immutable-baseline'
EOF
node_platforms=(linux linux)
node_architectures=(x64 arm64)
node_versions=(24.18.0 24.18.0)
for index in "${!node_platforms[@]}"; do
  node_global_key="${node_platforms[index]}-${node_architectures[index]}-node${node_versions[index]%%.*}"
  mkdir -p "$npm_base/$node_global_key/bin"
  cat > "$npm_base/$node_global_key/bin/opencode" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "side-installed:$node_global_key:\${NPM_CONFIG_PREFIX}:\${MSK_NPM_GLOBAL_ROOT}"
EOF
  chmod 755 "$npm_base/$node_global_key/bin/opencode"
done
chmod 755 "$fake/apptainer" "$fake/node" "$fake/opencode" "$bin/ct_shell.sh"

set +e
HOME="$home" XDG_DATA_HOME="$home/data" \
  NVIM_CONT_LOCATION="$image" MKCHAD_TEST_RUNTIME_LOG="$runtime_log" \
  SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 23 ]] || { printf '%s\n' 'nvim_shell did not use ct_shell.sh' >&2; exit 1; }

mapfile -t argv < "$runtime_log"
[[ ${argv[0]} == --apptainer \
  && ${argv[1]} == --ct-bind && ${argv[2]} == "$npm_base:/opt/msk/npm-global" \
  && ${argv[3]} == --ct-env && ${argv[4]} == MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  && ${argv[5]} == --ct-bootstrap && ${argv[6]} == "$bin/mkchad-container-bootstrap" \
  && ${argv[7]} == --ct-container-shell && ${argv[8]} == /bin/bash \
  && ${argv[9]} == -- && ${argv[10]} == "$image" ]] || {
  printf '%s\n' 'nvim_shell did not preserve the MkChad image launch contract' >&2
  exit 1
}

for index in "${!node_platforms[@]}"; do
  node_platform=${node_platforms[index]}
  node_architecture=${node_architectures[index]}
  node_version=${node_versions[index]}
  node_global_key="${node_platform}-${node_architecture}-node${node_version%%.*}"
  selection=$(MSK_NPM_GLOBAL_BASE="$npm_base" \
    MKCHAD_TEST_NODE_PLATFORM="$node_platform" \
    MKCHAD_TEST_NODE_ARCH="$node_architecture" \
    MKCHAD_TEST_NODE_VERSION="$node_version" PATH="$fake:$PATH" \
    "$bin/mkchad-container-bootstrap" opencode --version)
  expected_selection="side-installed:$node_global_key:$npm_base/$node_global_key:$npm_base/$node_global_key"
  [[ $selection == "$expected_selection" ]] || {
    printf 'container bootstrap did not select the writable %s npm prefix\n' "$node_global_key" >&2
    exit 1
  }
done

printf '%s\n' 'nvim_shell wrapper tests passed'
