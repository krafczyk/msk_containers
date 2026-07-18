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
printf '%s\n' 'linux-x64-node24'
EOF
cat > "$bin/ct_shell.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_RUNTIME_LOG"
exit 23
EOF
mkdir -p "$npm_base/linux-x64-node24/bin"
cat > "$fake/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'immutable-baseline'
EOF
cat > "$npm_base/linux-x64-node24/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'side-installed'
EOF
chmod 755 "$fake/apptainer" "$fake/node" "$fake/opencode" \
  "$npm_base/linux-x64-node24/bin/opencode" "$bin/ct_shell.sh"

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

selection=$(MSK_NPM_GLOBAL_BASE="$npm_base" PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" opencode --version)
[[ $selection == side-installed ]] || {
  printf '%s\n' 'container bootstrap did not prioritize the side-installed executable' >&2
  exit 1
}

printf '%s\n' 'nvim_shell wrapper tests passed'
