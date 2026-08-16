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
export XDG_STATE_HOME="$home/.local/state"
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
for launcher in container-tools ct_exec.sh ct_shell.sh ct_instance_exec.sh ct_mount_detector.sh ct_args.sh; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/$launcher"
  chmod 755 "$bin/$launcher"
done
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
cat > "$fake/singularity" <<'EOF'
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
write_launcher_stub "$bin/ct_instance_exec.sh" 23
write_launcher_stub "$bin/ct_exec.sh" 24
write_launcher_stub "$alternate_tools/ct_instance_exec.sh" 25
write_launcher_stub "$alternate_tools/ct_exec.sh" 26
for launcher in container-tools ct_shell.sh ct_mount_detector.sh ct_args.sh; do
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
chmod 755 "$fake/apptainer" "$fake/singularity" "$fake/node" "$fake/opencode"

set +e
env -u CT_ROOT HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 23 ]] || { printf '%s\n' 'nvim_shell did not use ct_instance_exec.sh' >&2; exit 1; }

mapfile -t argv < "$runtime_log"
argc=${#argv[@]}
[[ ${argv[0]} == --singularity \
  && ${argv[1]} == --ct-instance-root && ${argv[2]} == "$home/.local/share/mkchad/tmp/container-instances" \
  && ${argv[3]} == --ct-bind && ${argv[4]} == "$npm_base:/opt/msk/npm-global" \
  && ${argv[5]} == --ct-env && ${argv[6]} == MKCHAD_PERSISTENT_INSTANCE=1 \
  && ${argv[7]} == --ct-env && ${argv[8]} == MKCHAD_NVIM_IMAGE=1 \
  && ${argv[9]} == --ct-env && ${argv[10]} == NVIM_APPNAME=mkchad \
  && ${argv[argc - 9]} == --ct-bootstrap && ${argv[argc - 8]} == "$package_bin/mkchad-container-bootstrap" \
  && ${argv[argc - 7]} == -- && ${argv[argc - 6]} == "$image" \
  && ${argv[argc - 5]} == --mkchad-payload-cwd && ${argv[argc - 4]} == "$PWD" \
  && ${argv[argc - 3]} == -- && ${argv[argc - 2]} == --mkchad-generic-shell \
  && ${argv[argc - 1]} == -- ]] || {
  printf '%s\n' 'nvim_shell did not preserve the MkChad image launch contract' >&2
  exit 1
}
[[ $(<"$launcher_log") == "$package_bin/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'unset CT_ROOT did not use the installed co-located persistent launcher' >&2
  exit 1
}

plain_profile=("${argv[@]:0:argc-7}")
rm -f "$runtime_log" "$launcher_log"
set +e
env -u CT_ROOT HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell" -c 'printf shell-command'
command_status=$?
set -e
mapfile -t command_argv < "$runtime_log"
command_argc=${#command_argv[@]}
command_profile=("${command_argv[@]:0:command_argc-9}")
[[ $command_status -eq 23 \
  && ${#command_profile[@]} -eq ${#plain_profile[@]} \
  && ${command_argv[command_argc - 4]} == --mkchad-generic-shell \
  && ${command_argv[command_argc - 3]} == -- \
  && ${command_argv[command_argc - 2]} == -c \
  && ${command_argv[command_argc - 1]} == 'printf shell-command' ]] || {
  printf '%s\n' 'nvim_shell did not preserve shell arguments as payload-only data' >&2
  exit 1
}
for index in "${!plain_profile[@]}"; do
  [[ ${command_profile[index]} == "${plain_profile[index]}" ]] || {
    printf '%s\n' 'nvim_shell arguments changed the persistent profile identity inputs' >&2
    exit 1
  }
done

mv "$fake/singularity" "$fake/singularity.disabled"
set +e
HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
apptainer_shell_status=$?
set -e
mapfile -t apptainer_shell_argv < "$runtime_log"
[[ $apptainer_shell_status -eq 23 && ${apptainer_shell_argv[0]} == --apptainer ]] || {
  printf '%s\n' 'Apptainer-only nvim_shell launch selected the wrong backend' >&2
  exit 1
}
set +e
HOME="$home" NVIM_CONT_LOCATION="$image" MKCHAD_TEST_RUNTIME_LOG="$runtime_log" \
  MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" CT_ROOT="$alternate_link" PATH="$fake:$PATH" \
  "$bin/nvim" 'apptainer file'
apptainer_nvim_status=$?
set -e
mapfile -t apptainer_nvim_argv < "$runtime_log"
[[ $apptainer_nvim_status -eq 25 && ${apptainer_nvim_argv[0]} == --apptainer ]] || {
  printf '%s\n' 'Apptainer-only nvim launch selected the wrong backend' >&2
  exit 1
}
mv "$fake/singularity.disabled" "$fake/singularity"

rm -f "$runtime_log" "$launcher_log"
set +e
HOME="$home" XDG_DATA_HOME="$home/data" NVIM_CONT_LOCATION="$image" \
  MKCHAD_TEST_RUNTIME_LOG="$runtime_log" MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" \
  CT_ROOT='' SHELL=/missing/host-shell PATH="$fake:$PATH" "$bin/nvim_shell"
status=$?
set -e
[[ $status -eq 23 && $(<"$launcher_log") == "$package_bin/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'empty CT_ROOT did not use the installed co-located persistent launcher' >&2
  exit 1
}

rm -f "$runtime_log" "$launcher_log"
set +e
env -u NVIM_APPNAME HOME="$home" NVIM_CONT_LOCATION="$image" MKCHAD_TEST_RUNTIME_LOG="$runtime_log" \
  MKCHAD_TEST_LAUNCHER_LOG="$launcher_log" CT_ROOT="$alternate_link" PATH="$fake:$PATH" \
  "$bin/nvim" 'file with spaces'
status=$?
set -e
[[ $status -eq 25 && $(<"$launcher_log") == "$alternate_tools/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'nvim did not honor the canonical checkout-shaped CT_ROOT' >&2
  exit 1
}
mapfile -t nvim_argv < "$runtime_log"
[[ ${nvim_argv[0]} == --singularity \
  && " ${nvim_argv[*]} " == *" -- $image --mkchad-payload-cwd "* \
  && " ${nvim_argv[*]} " == *" -- --mkchad-generic-nvim unset  -- file with spaces "* ]] || {
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
[[ $status -eq 25 && $(<"$launcher_log") == "$alternate_tools/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'nvim_shell did not use the canonical checkout-shaped CT_ROOT' >&2
  exit 1
}
mapfile -t argv < "$runtime_log"
argc=${#argv[@]}
[[ ${argv[argc - 8]} == "$package_bin/mkchad-container-bootstrap" ]] || {
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

payload_cwd="$work/payload-cwd"
mkdir "$payload_cwd"
payload_pwd=$(MSK_NPM_GLOBAL_BASE="$npm_base" \
  MKCHAD_TEST_NODE_PLATFORM=linux \
  MKCHAD_TEST_NODE_ARCH=x64 \
  MKCHAD_TEST_NODE_VERSION=24.18.0 PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" --mkchad-payload-cwd "$payload_cwd" -- pwd)
[[ $payload_pwd == "$payload_cwd" ]] || {
  printf '%s\n' 'container bootstrap did not restore the payload working directory' >&2
  exit 1
}

cat > "$fake/nvim" <<'EOF'
#!/usr/bin/env bash
printf 'appname=%s cwd=%s\n' "${NVIM_APPNAME-unset}" "$PWD"
printf '%s\n' "$@"
EOF
chmod 755 "$fake/nvim"
generic_nvim_output=$(MSK_NPM_GLOBAL_BASE="$npm_base" \
  MKCHAD_TEST_NODE_PLATFORM=linux \
  MKCHAD_TEST_NODE_ARCH=x64 \
  MKCHAD_TEST_NODE_VERSION=24.18.0 PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" --mkchad-payload-cwd "$payload_cwd" -- \
  --mkchad-generic-nvim set caller-nvim -- 'generic file')
[[ $generic_nvim_output == $'appname=caller-nvim cwd='"$payload_cwd"$'\ngeneric file' ]] || {
  printf '%s\n' 'generic nvim payload did not restore the caller app name and working directory' >&2
  exit 1
}
generic_nvim_unset_output=$(NVIM_APPNAME=should-be-removed MSK_NPM_GLOBAL_BASE="$npm_base" \
  MKCHAD_TEST_NODE_PLATFORM=linux \
  MKCHAD_TEST_NODE_ARCH=x64 \
  MKCHAD_TEST_NODE_VERSION=24.18.0 PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" --mkchad-generic-nvim unset '' -- 'generic file')
[[ $generic_nvim_unset_output == $'appname=unset cwd='"$PWD"$'\ngeneric file' ]] || {
  printf '%s\n' 'unset NVIM_APPNAME did not select generic nvim' >&2
  exit 1
}

cat > "$fake/env" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_ENV_LOG"
exit 29
EOF
chmod 755 "$fake/env"
set +e
MSK_NPM_GLOBAL_BASE="$npm_base" MKCHAD_TEST_NODE_PLATFORM=linux \
  MKCHAD_TEST_NODE_ARCH=x64 MKCHAD_TEST_NODE_VERSION=24.18.0 \
  MKCHAD_TEST_ENV_LOG="$work/generic-shell-env.log" PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" --mkchad-generic-shell --
generic_shell_status=$?
set -e
[[ $generic_shell_status -eq 29 && $(<"$work/generic-shell-env.log") == $'-u\nNVIM_APPNAME\n/bin/bash\n-i' ]] || {
  printf '%s\n' 'generic shell payload did not start interactive /bin/bash without NVIM_APPNAME' >&2
  exit 1
}

set +e
MSK_NPM_GLOBAL_BASE="$npm_base" MKCHAD_TEST_NODE_PLATFORM=linux \
  MKCHAD_TEST_NODE_ARCH=x64 MKCHAD_TEST_NODE_VERSION=24.18.0 \
  MKCHAD_TEST_ENV_LOG="$work/generic-shell-command-env.log" PATH="$fake:$PATH" \
  "$bin/mkchad-container-bootstrap" --mkchad-generic-shell -- -c 'printf shell-command'
generic_shell_command_status=$?
set -e
[[ $generic_shell_command_status -eq 29 \
  && $(<"$work/generic-shell-command-env.log") == $'-u\nNVIM_APPNAME\n/bin/bash\n-c\nprintf shell-command' ]] || {
  printf '%s\n' 'generic shell payload did not preserve caller shell arguments' >&2
  exit 1
}

printf '%s\n' 'nvim_shell wrapper tests passed'
