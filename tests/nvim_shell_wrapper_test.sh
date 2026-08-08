#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/mkchad-v1}
wrapper=${2:?pass the nvim_shell path}
wrapper=$(realpath "$wrapper")
[[ $work == /tmp/mkchad-v1/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/mkchad-v1' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
fake="$work/fake-bin"
bin="$home/.local/bin"
image="$work/neovim.sif"
runtime_log="$work/runtime.log"
launcher_log="$work/launcher.log"
npm_base="$home/.local/share/msk_containers/npm-global"
repo=${wrapper%/nvim/bin/nvim_shell}
installer="$repo/bin/install_nvim.sh"
export CONTAINER_TOOLS_HOST_PACKAGE_ARCHIVE=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHIVE:?pass the verified host package archive}
export CONTAINER_TOOLS_HOST_PACKAGE_SHA256=${CONTAINER_TOOLS_HOST_PACKAGE_SHA256:?pass the host package SHA-256}
export CONTAINER_TOOLS_HOST_PACKAGE_VERSION=${CONTAINER_TOOLS_HOST_PACKAGE_VERSION:?pass the host package version}
export CONTAINER_TOOLS_HOST_PACKAGE_SOURCE_COMMIT=${CONTAINER_TOOLS_HOST_PACKAGE_SOURCE_COMMIT:?pass the host package source commit}
export CONTAINER_TOOLS_HOST_PACKAGE_ARCHITECTURE=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHITECTURE:?pass the host package architecture}
export CONTAINER_TOOLS_HOST_PACKAGE_LIBC=${CONTAINER_TOOLS_HOST_PACKAGE_LIBC:?pass the host package libc}
alternate_tools="$work/alternate/container_tools"
alternate_link="$work/alternate-link"
nonexecutable_tools="$work/nonexecutable"
mkdir -p "$home" "$fake" "$alternate_tools" "$nonexecutable_tools"
ln -s "$alternate_tools" "$alternate_link"
: > "$image"
HOME="$home" "$installer" >/dev/null
package_bin=$(realpath "$bin")
cmp "$repo/nvim/bin/ct_launcher.sh" "$bin/ct_launcher.sh"
# shellcheck disable=SC1090,SC1091 # Exercise the installed resolver copy directly.
. "$bin/ct_launcher.sh"
checkout_shell=$(CT_ROOT="$bin" ct_launcher_path ct_shell.sh)
[[ $checkout_shell == "$package_bin/ct_shell.sh" ]] || {
  printf '%s\n' 'CT_ROOT did not resolve the installed package bin directory' >&2
  exit 1
}

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
write_launcher_stub() {
  local path=$1 status=$2
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\$MKCHAD_TEST_RUNTIME_LOG"
printf '%s\\n' "\$0" > "\$MKCHAD_TEST_LAUNCHER_LOG"
exit $status
EOF
  chmod 755 "$path"
}
write_launcher_stub "$bin/ct_shell.sh" 23
write_launcher_stub "$bin/ct_exec.sh" 24
write_launcher_stub "$alternate_tools/ct_shell.sh" 25
write_launcher_stub "$alternate_tools/ct_exec.sh" 26
for launcher in container-tools ct_instance_exec.sh ct_mount_detector.sh ct_args.sh; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$alternate_tools/$launcher"
  chmod 755 "$alternate_tools/$launcher"
done
printf '%s\n' '#!/usr/bin/env bash' > "$nonexecutable_tools/ct_shell.sh"
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
chmod 755 "$fake/apptainer" "$fake/node" "$fake/opencode"

set +e
env -u CT_ROOT HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 23 ]] || { printf '%s\n' 'nvim_shell did not use ct_shell.sh' >&2; exit 1; }

mapfile -t argv < "$runtime_log"
[[ ${argv[0]} == --apptainer \
  && ${argv[1]} == --ct-bind && ${argv[2]} == "$npm_base:/opt/msk/npm-global" \
  && ${argv[3]} == --ct-env && ${argv[4]} == MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  && ${argv[5]} == --ct-bootstrap && ${argv[6]} == "$package_bin/mkchad-container-bootstrap" \
  && ${argv[7]} == --ct-container-shell && ${argv[8]} == /bin/bash \
  && ${argv[9]} == -- && ${argv[10]} == "$image" ]] || {
  printf '%s\n' 'nvim_shell did not preserve the MkChad image launch contract' >&2
  exit 1
}
[[ $(<"$launcher_log") == "$package_bin/ct_shell.sh" ]] || {
  printf '%s\n' 'unset CT_ROOT did not use the installed co-located shell launcher' >&2
  exit 1
}

rm -f "$runtime_log" "$launcher_log"
set +e
HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  CT_ROOT='' SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 23 && $(<"$launcher_log") == "$package_bin/ct_shell.sh" ]] || {
  printf '%s\n' 'empty CT_ROOT did not use the installed co-located shell launcher' >&2
  exit 1
}

rm -f "$runtime_log" "$launcher_log"
set +e
env -u NVIM_APPNAME HOME="$home" NVIM_CONT_LOCATION="$image" MKCHAD_TEST_RUNTIME_LOG="$runtime_log" \
  MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" CT_ROOT="$alternate_link" PATH="$fake:$PATH" \
  "$bin/nvim" 'file with spaces'
status=$?
set -e
[[ $status -eq 26 && $(<"$launcher_log") == "$alternate_tools/ct_exec.sh" ]] || {
  printf '%s\n' 'nvim did not honor the canonical checkout-shaped CT_ROOT' >&2
  exit 1
}
mapfile -t nvim_argv < "$runtime_log"
[[ ${nvim_argv[0]} == --apptainer && ${nvim_argv[1]} == "$image" \
  && ${nvim_argv[2]} == nvim && ${nvim_argv[3]} == 'file with spaces' ]] || {
  printf '%s\n' 'nvim did not preserve its container launch payload' >&2
  exit 1
}

rm -f "$runtime_log" "$launcher_log"
set +e
HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  CT_ROOT="$alternate_link" SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 25 && $(<"$launcher_log") == "$alternate_tools/ct_shell.sh" ]] || {
  printf '%s\n' 'nvim_shell did not use the canonical checkout-shaped CT_ROOT' >&2
  exit 1
}
mapfile -t argv < "$runtime_log"
[[ ${argv[6]} == "$package_bin/mkchad-container-bootstrap" ]] || {
  printf '%s\n' 'CT_ROOT redirected the launcher-relative container bootstrap' >&2
  exit 1
}

expect_closed_root_failure() {
  local label=$1 root=$2 expected=$3 status
  rm -f "$runtime_log" "$launcher_log"
  set +e
  HOME="$home" NVIM_CONT_LOCATION="$image" MKCHAD_TEST_RUNTIME_LOG="$runtime_log" \
    MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" CT_ROOT="$root" PATH="$fake:$PATH" \
    "$bin/nvim_shell" >"$work/$label.out" 2>"$work/$label.err"
  status=$?
  set -e
  [[ $status -ne 0 && $(<"$work/$label.err") == *"$expected"* \
    && ! -e $runtime_log && ! -e $launcher_log ]] || {
    printf 'CT_ROOT %s did not fail closed\n' "$label" >&2
    exit 1
  }
}

expect_closed_root_failure relative relative-root 'CT_ROOT must be an absolute path'
expect_closed_root_failure missing "$work/missing-root" 'CT_ROOT is not an existing directory'
expect_closed_root_failure raw-checkout "$repo/container_tools" 'not a complete container-tools package bin directory'
expect_closed_root_failure nonexecutable "$nonexecutable_tools" 'not a complete container-tools package bin directory'

# Losing the sourced helper must fail closed instead of deriving `.` from an
# empty realpath result and executing a launcher from the working directory.
vanishing_root="$work/vanishing-helper"
attacker_root="$work/attacker-cwd"
mkdir "$vanishing_root" "$attacker_root"
cp "$bin/ct_launcher.sh" "$vanishing_root/ct_launcher.sh"
write_launcher_stub "$attacker_root/ct_shell.sh" 27
if bash -c '
  set -euo pipefail
  . "$1"
  rm -- "$1"
  cd "$2"
  CT_ROOT= ct_launcher_path ct_shell.sh
' bash "$vanishing_root/ct_launcher.sh" "$attacker_root" >"$work/vanishing.out" 2>"$work/vanishing.err"; then
  printf '%s\n' 'missing co-located helper resolved a launcher from the working directory' >&2
  exit 1
fi
[[ $(<"$work/vanishing.err") == *'cannot resolve co-located launcher directory'* ]] || {
  printf '%s\n' 'missing co-located helper did not emit the closed failure diagnostic' >&2
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
