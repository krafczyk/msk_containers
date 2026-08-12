#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/mkchad-v1}
wrapper=${2:?pass the wrapper path}
wrapper=$(realpath "$wrapper")
[[ $work == /tmp/mkchad-v1/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/mkchad-v1' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
config="$work/config"
state_default="$home/.local/state"
fake="$work/fake-bin"
bin="$home/.local/bin"
container_dir="$home/containers"
image_target="$container_dir/neovim_test.sif"
image="$container_dir/neovim.sif"
runtime_log="$work/runtime.log"
launcher_log="$home/launcher.log"
status_log="$home/runtime.log"
nvim_log="$work/nvim.log"
installed_wrapper="$bin/mkchad-opencode-server"
installed_image_command="$bin/mkchad-opencode-server-image"
installed_mkchad="$bin/mkchad"
installed_nvim="$bin/nvim"
installed_nvim_shell="$bin/nvim_shell"
mount_config="$work/ct_mount.conf"
repo=${wrapper%/nvim/bin/mkchad-opencode-server}
installer="$repo/bin/install_nvim.sh"
export CONTAINER_TOOLS_HOST_PACKAGE_ARCHIVE=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHIVE:?pass the verified host package archive}
export CONTAINER_TOOLS_HOST_PACKAGE_SHA256=${CONTAINER_TOOLS_HOST_PACKAGE_SHA256:?pass the host package SHA-256}
export CONTAINER_TOOLS_HOST_PACKAGE_VERSION=${CONTAINER_TOOLS_HOST_PACKAGE_VERSION:?pass the host package version}
export CONTAINER_TOOLS_HOST_PACKAGE_SOURCE_COMMIT=${CONTAINER_TOOLS_HOST_PACKAGE_SOURCE_COMMIT:?pass the host package source commit}
export CONTAINER_TOOLS_HOST_PACKAGE_ARCHITECTURE=${CONTAINER_TOOLS_HOST_PACKAGE_ARCHITECTURE:?pass the host package architecture}
export CONTAINER_TOOLS_HOST_PACKAGE_LIBC=${CONTAINER_TOOLS_HOST_PACKAGE_LIBC:?pass the host package libc}
alternate_tools="$work/alternate/container_tools"
alternate_link="$work/alternate-link"
mkdir -p "$home" "$config/mkchad/lua/mkchad/opencode" "$fake" "$container_dir" "$alternate_tools"
ln -s "$alternate_tools" "$alternate_link"
: > "$config/mkchad/lua/mkchad/opencode/command.lua"
chmod 700 "$container_dir"
: > "$image_target"
chmod 600 "$image_target"
ln -s "${image_target##*/}" "$image"
: > "$mount_config"
HOME="$home" "$installer" >/dev/null
package_bin=$(realpath "$bin")
real_container_tools="$work/container-tools-build"
cmake -S "$repo/container_tools" -B "$real_container_tools" \
  -D CMAKE_BUILD_TYPE=Release -D CONTAINER_TOOLS_STATIC=OFF >/dev/null
cmake --build "$real_container_tools" >/dev/null
real_container_tools="$real_container_tools/container-tools"
for launcher in container-tools ct_exec.sh ct_shell.sh ct_instance_exec.sh ct_mount_detector.sh ct_args.sh; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/$launcher"
  chmod 755 "$bin/$launcher"
done

cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'apptainer version 1.3.6'
  exit 0
fi
exit 64
EOF
cat > "$fake/singularity-real" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'singularity-ce version 4.2.1'
  exit 0
fi
exit 64
EOF
ln -s singularity-real "$fake/singularity"
cat > "$bin/ct_instance_exec.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MKCHAD_TEST_RUNTIME_LOG"
[[ -z ${MKCHAD_TEST_LAUNCHER_CWD_LOG:-} ]] || printf '%s\n' "$PWD" > "$MKCHAD_TEST_LAUNCHER_CWD_LOG"
printf 'ct_instance_exec:%s\n' "$0" >> "$HOME/launcher.log"
printf 'mount_config=%s\n' "${CT_MOUNT_CFG:-}" >> "$MKCHAD_TEST_RUNTIME_LOG"
exit 23
EOF
cat > "$bin/ct_exec.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/runtime.log"
printf 'ct_exec:%s\n' "$0" >> "$HOME/launcher.log"
container_env=()
while (($#)); do
  case "$1" in
    --ct-env) container_env+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
image=$1
shift
env "${container_env[@]}" SINGULARITY_CONTAINER="$image" "$@"
EOF
cp "$bin/ct_instance_exec.sh" "$alternate_tools/ct_instance_exec.sh"
cp "$bin/ct_exec.sh" "$alternate_tools/ct_exec.sh"
for launcher in container-tools ct_shell.sh ct_mount_detector.sh ct_args.sh; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$alternate_tools/$launcher"
  chmod 755 "$alternate_tools/$launcher"
done
cat > "$fake/nvim" <<'EOF'
#!/usr/bin/env bash
log=${MKCHAD_TEST_NVIM_LOG:-"${XDG_CONFIG_HOME%/*}/nvim.log"}
printf '%s\n' "$@" > "$log"
printf 'marker=%s home=%s state=%s runtime=%s cache=%s data=%s base=%s root=%s prefix=%s config=%s log=%s path=%s\n' "${MKCHAD_NVIM_IMAGE:-}" "${HOME:-}" "${XDG_STATE_HOME:-}" "${XDG_RUNTIME_DIR:-}" "${XDG_CACHE_HOME:-}" "${XDG_DATA_HOME:-}" "${MSK_NPM_GLOBAL_BASE:-}" "${MSK_NPM_GLOBAL_ROOT:-}" "${NPM_CONFIG_PREFIX:-}" "${OPENCODE_CONFIG:-}" "${NVIM_LOG_FILE:-}" "$PATH" >> "$log"
exit 19
EOF
cat > "$fake/node" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -p ]] || exit 64
printf '%s\n' 'linux-x64-node24'
EOF
chmod 755 "$fake/apptainer" "$fake/singularity-real" "$fake/nvim" "$fake/node" "$bin/ct_instance_exec.sh" "$bin/ct_exec.sh" \
  "$alternate_tools/ct_instance_exec.sh" "$alternate_tools/ct_exec.sh"

persistent_profile() {
  local argument
  while IFS= read -r argument; do
    [[ $argument == -- ]] && break
    if [[ $argument == --ct-env ]]; then
      IFS= read -r argument || return 1
      continue
    fi
    printf '%s\0' "$argument"
  done < "$1"
}

persistent_identity() {
  local log=$1
  local -a arguments
  mapfile -t arguments < "$log"
  (
    cd "$home"
    env HOME="$home" XDG_STATE_HOME="$state_default" PATH="$fake:$PATH" \
      CT_MOUNT_CFG="$mount_config" "$real_container_tools" instance identity "${arguments[@]}"
  )
}

base_env=(
  "HOME=$home"
  "XDG_CONFIG_HOME=$config"
  "XDG_STATE_HOME=$state_default"
  "XDG_RUNTIME_DIR=$work/host-runtime"
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
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER -u XDG_STATE_HOME -u CT_ROOT "${base_env[@]}" MKCHAD_NVIM_CONTAINER=1 "$installed_wrapper" status --json
host_status=$?
set -e
[[ $host_status -eq 19 ]] || { printf '%s\n' 'status did not use the foreground container executor' >&2; exit 1; }
[[ $(<"$launcher_log") == "ct_exec:$package_bin/ct_exec.sh" ]] || {
  printf '%s\n' 'unset CT_ROOT did not use the installed co-located foreground launcher' >&2; exit 1;
}
mapfile -t runtime_argv < "$status_log"
[[ ${runtime_argv[0]} == --singularity \
  && ${runtime_argv[1]} == --ct-bind && ${runtime_argv[2]} == "$config:$config:ro" \
  && ${runtime_argv[3]} == --ct-env && ${runtime_argv[4]} == MKCHAD_NVIM_IMAGE=1 \
  && ${runtime_argv[5]} == --ct-env && ${runtime_argv[6]} == NVIM_APPNAME=mkchad \
  && ${runtime_argv[7]} == --ct-env && ${runtime_argv[8]} == "XDG_CONFIG_HOME=$config" \
  && ${runtime_argv[9]} == --ct-env && ${runtime_argv[10]} == "XDG_STATE_HOME=$state_default" \
  && ${runtime_argv[11]} == --ct-env && ${runtime_argv[12]} == "XDG_CACHE_HOME=$home/.local/cache" \
  && ${runtime_argv[13]} == --ct-env && ${runtime_argv[14]} == "XDG_DATA_HOME=$home/.local/share" \
  && ${runtime_argv[15]} == --ct-env && ${runtime_argv[16]} == MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  && ${runtime_argv[17]} == --ct-bootstrap && ${runtime_argv[18]} == "$package_bin/mkchad-container-bootstrap" \
  && ${runtime_argv[19]} == -- && ${runtime_argv[20]} == "$image" \
  && ${runtime_argv[21]} == /usr/bin/env && ${runtime_argv[22]} == HOME=/nonexistent \
  && ${runtime_argv[23]} == "$package_bin/mkchad-opencode-server-image" && ${runtime_argv[24]} == status \
  && ${runtime_argv[25]} == --json && ${runtime_argv[26]} == --host-evidence-v1 ]] || {
  printf '%s\n' 'status foreground transport argv changed' >&2; exit 1;
}
python3 - "${runtime_argv[27]}" "$fake/singularity-real" <<'PY'
import base64
import json
import os
import sys

encoded = sys.argv[1]
assert len(encoded) <= 6144 and "=" not in encoded
payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
assert payload["schema"] == 1
assert payload["container_runtime"]["state"] == "present"
assert payload["container_runtime"]["family"] == "singularity"
expected_runtime = os.stat(sys.argv[2])
assert payload["container_runtime"]["executable_identity"].split(":", 3)[:2] == [
    str(expected_runtime.st_dev), str(expected_runtime.st_ino)
]
assert payload["selected_image"]["identity_kind"] == "host-file-stat-v1"
assert payload["persisted_instance"] == {"state": "absent"}
assert all("/" not in str(value) for value in payload.values())
PY
[[ ! -e $state_default && ! -e $home/.local/cache && ! -e $home/.local/share/mkchad ]] || {
  printf '%s\n' 'clean-home status created mutable runtime state' >&2; exit 1;
}
[[ $(<"$nvim_log") == *"marker=1 home=/nonexistent state=$state_default runtime=/nonexistent/.local/share/mkchad/tmp cache=$home/.local/cache data=$home/.local/share base=/opt/msk/npm-global"* ]] || {
  printf '%s\n' 'status did not preserve its clean-home XDG environment in the image' >&2; exit 1;
}

rm -f "$launcher_log"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" CT_ROOT="$alternate_link" \
  "$installed_wrapper" status --json
alternate_status=$?
set -e
[[ $alternate_status -eq 19 && $(<"$launcher_log") == "ct_exec:$alternate_tools/ct_exec.sh" ]] || {
  printf '%s\n' 'status did not use the canonical checkout-shaped CT_ROOT' >&2; exit 1;
}
mapfile -t alternate_status_argv < "$status_log"
[[ ${alternate_status_argv[18]} == "$package_bin/mkchad-container-bootstrap" ]] || {
  printf '%s\n' 'CT_ROOT redirected the launcher-relative server bootstrap' >&2; exit 1;
}

mkdir -p "$home/.local/share/mkchad"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" "$installed_wrapper" status --json
existing_data_status=$?
set -e
[[ $existing_data_status -eq 19 ]] || { printf '%s\n' 'status did not execute with existing MkChad data' >&2; exit 1; }
mapfile -t existing_data_argv < "$status_log"
mkchad_data_bind=0
data_home_bind=0
for ((index = 0; index < ${#existing_data_argv[@]}; index++)); do
  [[ ${existing_data_argv[index]} != "$home/.local/share/mkchad:$home/.local/share/mkchad:ro" ]] || mkchad_data_bind=1
  [[ ${existing_data_argv[index]} != "$home/.local/share:$home/.local/share:ro" ]] || data_home_bind=1
done
[[ $mkchad_data_bind == 1 && $data_home_bind == 0 ]] || {
  printf '%s\n' 'status did not bind only the existing MkChad data subtree read-only' >&2; exit 1;
}

helper="$bin/mkchad-status-host-evidence"
instance_root="$home/.local/share/mkchad/tmp/container-instances"
mkdir -p "$instance_root"
chmod 700 "$instance_root"
record="$instance_root/mkchad-0123456789abcdef0123456789abcdef.identity"
record_identity=$(LC_ALL=C stat -Lc '%d:%i:%s:%y:%z' -- "$image_target")
printf 'name=mkchad-0123456789abcdef0123456789abcdef\nimage=%s\nidentity=%s\n' \
  "$image_target" "$record_identity" > "$record"
chmod 600 "$record"
record_before=$(LC_ALL=C stat -Lc '%d:%i:%s:%y:%z' -- "$record")
record_bytes=$(base64 -w 0 < "$record")
evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
python3 - "$evidence" <<'PY'
import base64
import json
import sys

payload = json.loads(base64.urlsafe_b64decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 4)))
assert payload["persisted_instance"]["state"] == "present"
assert payload["persisted_instance"]["label"] == "mkchad-0123456789abcdef0123456789abcdef"
assert payload["persisted_instance"]["identity_kind"] == "host-file-stat-v1"
assert "/" not in str(payload["persisted_instance"])
PY
[[ $(LC_ALL=C stat -Lc '%d:%i:%s:%y:%z' -- "$record") == "$record_before" \
  && $(base64 -w 0 < "$record") == "$record_bytes" ]] || {
  printf '%s\n' 'status evidence rewrote existing instance metadata' >&2; exit 1;
}

image_target_rotated="$container_dir/neovim_rotated.sif"
: > "$image_target_rotated"
chmod 600 "$image_target_rotated"
ln -sfn "${image_target_rotated##*/}" "$image"
rotated_record="$instance_root/mkchad-fedcba9876543210fedcba9876543210.identity"
rotated_identity=$(LC_ALL=C stat -Lc '%d:%i:%s:%y:%z' -- "$image_target_rotated")
printf 'name=mkchad-fedcba9876543210fedcba9876543210\nimage=%s\nidentity=%s\n' \
  "$image_target_rotated" "$rotated_identity" > "$rotated_record"
chmod 600 "$rotated_record"
evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
python3 - "$evidence" "$image_target_rotated" <<'PY'
import base64
import json
import os
import sys

payload = json.loads(base64.urlsafe_b64decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 4)))
expected = os.stat(sys.argv[2])
assert payload["selected_image"]["identity_kind"] == "host-file-stat-v1"
assert payload["selected_image"]["identity"].split(":", 3)[:3] == [str(expected.st_dev), str(expected.st_ino), str(expected.st_size)]
assert payload["persisted_instance"]["state"] == "present"
assert payload["persisted_instance"]["label"] == "mkchad-fedcba9876543210fedcba9876543210"
PY

duplicate_record="$instance_root/mkchad-00112233445566778899aabbccddeeff.identity"
printf 'name=mkchad-00112233445566778899aabbccddeeff\nimage=%s\nidentity=%s\n' \
  "$image_target_rotated" "$rotated_identity" > "$duplicate_record"
chmod 600 "$duplicate_record"
ambiguous_evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
rm -f "$duplicate_record"
rm -f "$rotated_record"
no_match_evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
unsafe_record="$instance_root/mkchad-11223344556677889900aabbccddeeff.identity"
ln -s "$image_target_rotated" "$unsafe_record"
unsafe_evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
rm -f "$unsafe_record"
python3 - "$ambiguous_evidence" "$no_match_evidence" "$unsafe_evidence" <<'PY'
import base64
import json
import sys

for encoded in sys.argv[1:]:
    payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    assert payload["persisted_instance"] == {"state": "unavailable"}
    assert payload["selected_image"]["identity_kind"] == "host-file-stat-v1"
PY

for index in {1..64}; do
  printf -v suffix '%032x' "$index"
  overflow_record="$instance_root/mkchad-$suffix.identity"
  printf 'name=mkchad-%s\nimage=%s\nidentity=%s\n' "$suffix" "$image_target" "$record_identity" > "$overflow_record"
  chmod 600 "$overflow_record"
done
overflow_evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
python3 - "$overflow_evidence" <<'PY'
import base64
import json
import sys

payload = json.loads(base64.urlsafe_b64decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 4)))
assert payload["persisted_instance"] == {"state": "unavailable"}
assert payload["selected_image"]["identity_kind"] == "host-file-stat-v1"
PY
for index in {1..64}; do
  printf -v suffix '%032x' "$index"
  rm -f "$instance_root/mkchad-$suffix.identity"
done

chmod 770 "$instance_root"
unsafe_evidence=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
chmod 700 "$instance_root"
chmod 666 "$image_target_rotated"
unsafe_selector=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image" \
  --container-dir "$container_dir" --instance-root "$instance_root")
chmod 600 "$image_target_rotated"
noncanonical_selector=$(env "${base_env[@]}" "$helper" --runtime apptainer --runtime-executable "$fake/apptainer" --image "$image_target_rotated" \
  --container-dir "$container_dir" --instance-root "$instance_root")
python3 - "$unsafe_evidence" "$unsafe_selector" "$noncanonical_selector" <<'PY'
import base64
import json
import sys

def read(value):
    return json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))

assert read(sys.argv[1])["persisted_instance"] == {"state": "unavailable"}
assert read(sys.argv[2])["selected_image"] == {"state": "unavailable"}
assert read(sys.argv[3])["selected_image"] == {"state": "unavailable"}
PY

cat > "$fake/singularity" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
chmod 755 "$fake/singularity"
SECONDS=0
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" "$installed_wrapper" status --json
timeout_status=$?
set -e
[[ $timeout_status -eq 19 && $SECONDS -lt 4 ]] || {
  printf '%s\n' 'host evidence timeout did not preserve foreground status bounds' >&2; exit 1;
}
mapfile -t timeout_argv < "$status_log"
timeout_host_evidence=
for ((index = 0; index < ${#timeout_argv[@]} - 1; index++)); do
  if [[ ${timeout_argv[index]} == --host-evidence-v1 ]]; then
    timeout_host_evidence=${timeout_argv[index + 1]}
    break
  fi
done
[[ -n $timeout_host_evidence ]] || { printf '%s\n' 'timeout status omitted host evidence' >&2; exit 1; }
python3 - "$timeout_host_evidence" <<'PY'
import base64
import json
import sys

payload = json.loads(base64.urlsafe_b64decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 4)))
assert all(value == {"state": "unavailable"} for key, value in payload.items() if key != "schema")
PY
cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'apptainer version 1.3.6'
  exit 0
fi
exit 64
EOF
chmod 755 "$fake/apptainer"

rm -f "$runtime_log" "$launcher_log"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  CT_ROOT="$alternate_link" "$installed_mkchad" 'file with spaces' >"$work/mkchad.out"
mkchad_status=$?
set -e
[[ $mkchad_status -eq 23 ]] || { printf '%s\n' 'MkChad launcher did not preserve instance payload status' >&2; exit 1; }
[[ $(<"$launcher_log") == "ct_instance_exec:$alternate_tools/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'MkChad launcher did not use CT_ROOT for persistent dispatch' >&2; exit 1;
}
mapfile -t mkchad_runtime_argv < "$runtime_log"
[[ ${mkchad_runtime_argv[0]} == --singularity \
  && ${mkchad_runtime_argv[1]} == --ct-instance-root \
  && ${mkchad_runtime_argv[2]} == "$home/.local/share/mkchad/tmp/container-instances" \
  && ${mkchad_runtime_argv[5]} == --ct-env && ${mkchad_runtime_argv[6]} == MKCHAD_PERSISTENT_INSTANCE=1 \
  && ${mkchad_runtime_argv[13]} == --ct-env && ${mkchad_runtime_argv[14]} == "XDG_STATE_HOME=$state_default" \
  && ${mkchad_runtime_argv[21]} == --ct-env && ${mkchad_runtime_argv[22]} == MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  && ${mkchad_runtime_argv[23]} == --ct-env && ${mkchad_runtime_argv[24]} == "OPENCODE_CONFIG=$config/mkchad/opencode.jsonc" \
  && ${mkchad_runtime_argv[25]} == --ct-bootstrap && ${mkchad_runtime_argv[26]} == "$package_bin/mkchad-container-bootstrap" \
  && ${mkchad_runtime_argv[27]} == -- && ${mkchad_runtime_argv[28]} == "$image" \
  && ${mkchad_runtime_argv[29]} == --mkchad-payload-cwd \
  && ${mkchad_runtime_argv[31]} == -- && ${mkchad_runtime_argv[32]} == --mkchad-nvim \
  && ${mkchad_runtime_argv[33]} == 'file with spaces' ]] || {
  printf '%s\n' 'MkChad launcher did not use the shared persistent instance contract' >&2; exit 1;
}

server_cwd="$work/server-cwd"
editor_cwd="$work/editor-[cwd],(punctuation)"
generic_nvim_cwd="$work/generic-nvim-cwd"
shell_cwd="$work/shell-cwd"
server_cwd_log="$work/server-cwd.log"
editor_cwd_log="$work/editor-cwd.log"
generic_nvim_cwd_log="$work/generic-nvim-cwd.log"
shell_cwd_log="$work/shell-cwd.log"
mkdir "$server_cwd" "$editor_cwd" "$generic_nvim_cwd" "$shell_cwd"
: > "$launcher_log"
set +e
(
  cd "$server_cwd"
  env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
    MKCHAD_TEST_LAUNCHER_CWD_LOG="$server_cwd_log" CT_ROOT="$alternate_link" \
    "$installed_wrapper" start --json
)
server_profile_status=$?
set -e
[[ $server_profile_status -eq 23 ]] || {
  printf '%s\n' 'server launch did not reach the persistent executor' >&2; exit 1;
}
cp "$runtime_log" "$work/server-persistent-profile.log"

set +e
(
  cd "$editor_cwd"
  env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
    MKCHAD_TEST_LAUNCHER_CWD_LOG="$editor_cwd_log" CT_ROOT="$alternate_link" \
    "$installed_mkchad" 'file with spaces'
)
editor_profile_status=$?
set -e
[[ $editor_profile_status -eq 23 ]] || {
  printf '%s\n' 'MkChad launch did not reach the persistent executor' >&2; exit 1;
}
cp "$runtime_log" "$work/editor-persistent-profile.log"

set +e
(
  cd "$generic_nvim_cwd"
  env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
    NVIM_APPNAME=generic-nvim MKCHAD_TEST_LAUNCHER_CWD_LOG="$generic_nvim_cwd_log" CT_ROOT="$alternate_link" \
    "$installed_nvim" 'generic file with spaces'
)
generic_nvim_profile_status=$?
set -e
[[ $generic_nvim_profile_status -eq 23 ]] || {
  printf '%s\n' 'generic nvim launch did not reach the persistent executor' >&2; exit 1;
}
cp "$runtime_log" "$work/generic-nvim-persistent-profile.log"

set +e
(
  cd "$shell_cwd"
  env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER -u NVIM_APPNAME "${base_env[@]}" \
    MKCHAD_TEST_LAUNCHER_CWD_LOG="$shell_cwd_log" CT_ROOT="$alternate_link" "$installed_nvim_shell"
)
shell_profile_status=$?
set -e
[[ $shell_profile_status -eq 23 ]] || {
  printf '%s\n' 'nvim_shell launch did not reach the persistent executor' >&2; exit 1;
}
cp "$runtime_log" "$work/nvim-shell-persistent-profile.log"

mapfile -t persistent_dispatches < "$launcher_log"
[[ ${#persistent_dispatches[@]} -eq 4 ]] || {
  printf '%s\n' 'all four launchers did not dispatch one persistent executor call' >&2; exit 1;
}
for persistent_dispatch in "${persistent_dispatches[@]}"; do
  [[ $persistent_dispatch == "ct_instance_exec:$alternate_tools/ct_instance_exec.sh" ]] || {
    printf '%s\n' 'a persistent launcher did not dispatch ct_instance_exec.sh' >&2; exit 1;
  }
done

cmp <(persistent_profile "$work/server-persistent-profile.log") \
  <(persistent_profile "$work/editor-persistent-profile.log") || {
  printf '%s\n' 'server and editor persistent profile arguments differ' >&2; exit 1;
}
server_identity=$(persistent_identity "$work/server-persistent-profile.log")
editor_identity=$(persistent_identity "$work/editor-persistent-profile.log")
generic_nvim_identity=$(persistent_identity "$work/generic-nvim-persistent-profile.log")
shell_identity=$(persistent_identity "$work/nvim-shell-persistent-profile.log")
[[ $server_identity =~ ^[0-9a-f]{64}$ && $editor_identity == "$server_identity" \
  && $generic_nvim_identity == "$server_identity" && $shell_identity == "$server_identity" ]] || {
  printf '%s\n' 'all four launchers did not produce the same container-tools identity' >&2; exit 1;
}
[[ $(<"$server_cwd_log") == $(<"$editor_cwd_log") \
  && $(<"$editor_cwd_log") == $(<"$generic_nvim_cwd_log") \
  && $(<"$generic_nvim_cwd_log") == $(<"$shell_cwd_log") ]] || {
  printf '%s\n' 'persistent launchers use different profile CWDs' >&2; exit 1;
}
[[ $(<"$server_cwd_log") == "$home" && $(<"$editor_cwd_log") == "$home" \
  && $(<"$generic_nvim_cwd_log") == "$home" && $(<"$shell_cwd_log") == "$home" ]] || {
  printf '%s\n' 'shared persistent profile did not use the canonical launcher CWD' >&2; exit 1;
}
mapfile -t editor_profile_argv < "$work/editor-persistent-profile.log"
[[ " ${editor_profile_argv[*]} " == *" --mkchad-payload-cwd $editor_cwd -- --mkchad-nvim "* ]] || {
  printf '%s\n' 'MkChad payload did not retain its caller working directory' >&2; exit 1;
}
mapfile -t server_profile_argv < "$work/server-persistent-profile.log"
[[ " ${server_profile_argv[*]} " == *" --mkchad-payload-cwd $server_cwd -- $package_bin/mkchad-opencode-server-image "* ]] || {
  printf '%s\n' 'server payload did not retain its caller working directory' >&2; exit 1;
}
mapfile -t generic_nvim_profile_argv < "$work/generic-nvim-persistent-profile.log"
[[ " ${generic_nvim_profile_argv[*]} " == *" --mkchad-payload-cwd $generic_nvim_cwd -- --mkchad-generic-nvim set generic-nvim -- generic file with spaces "* ]] || {
  printf '%s\n' 'generic nvim payload did not retain its caller app name and working directory' >&2; exit 1;
}
mapfile -t shell_profile_argv < "$work/nvim-shell-persistent-profile.log"
[[ " ${shell_profile_argv[*]} " == *" --mkchad-payload-cwd $shell_cwd -- --mkchad-generic-shell -- "* ]] || {
  printf '%s\n' 'nvim_shell payload did not retain its generic interactive-shell contract' >&2; exit 1;
}

custom_state="$work/state root"
mkdir -p "$custom_state"
rm -f "$runtime_log" "$launcher_log"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  "XDG_STATE_HOME=$custom_state" CT_ROOT="$alternate_link" "$installed_wrapper" start --json
custom_status=$?
set -e
[[ $custom_status -eq 23 ]] || { printf '%s\n' 'custom state host invocation did not preserve container status' >&2; exit 1; }
[[ $(<"$launcher_log") == "ct_instance_exec:$alternate_tools/ct_instance_exec.sh" ]] || {
  printf '%s\n' 'persistent server dispatch did not use CT_ROOT' >&2; exit 1;
}
mapfile -t custom_runtime_argv < "$runtime_log"
[[ ${custom_runtime_argv[0]} == --singularity \
  && ${custom_runtime_argv[3]} == --ct-bind \
  && ${custom_runtime_argv[4]} == "$home/.local/share/msk_containers/npm-global:/opt/msk/npm-global" \
  && ${custom_runtime_argv[5]} == --ct-bind \
  && ${custom_runtime_argv[6]} == "$custom_state:$custom_state" \
  && ${custom_runtime_argv[15]} == --ct-env \
  && ${custom_runtime_argv[16]} == "XDG_STATE_HOME=$custom_state" \
  && ${custom_runtime_argv[25]} == --ct-env \
  && ${custom_runtime_argv[26]} == "OPENCODE_CONFIG=$config/mkchad/opencode.jsonc" \
  && ${custom_runtime_argv[27]} == --ct-bootstrap \
  && ${custom_runtime_argv[35]} == start && ${custom_runtime_argv[36]} == --json ]] || {
  printf '%s\n' 'custom state root was not forwarded and bound identically' >&2; exit 1;
}
cp "$runtime_log" "$work/custom-server-persistent-profile.log"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  "XDG_STATE_HOME=$custom_state" CT_ROOT="$alternate_link" \
  "$installed_mkchad" 'custom state file'
custom_editor_status=$?
set -e
[[ $custom_editor_status -eq 23 ]] || {
  printf '%s\n' 'custom state MkChad launch did not reach the persistent executor' >&2; exit 1;
}
cmp <(persistent_profile "$work/custom-server-persistent-profile.log") \
  <(persistent_profile "$runtime_log") || {
  printf '%s\n' 'custom state server and editor persistent profile arguments differ' >&2; exit 1;
}

mv "$fake/singularity" "$fake/singularity.disabled"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  "$installed_wrapper" status --json
apptainer_status_status=$?
set -e
[[ $apptainer_status_status -eq 19 ]] || {
  printf '%s\n' 'Apptainer-only status did not use the foreground executor' >&2; exit 1;
}
mapfile -t apptainer_status_argv < "$status_log"
[[ ${apptainer_status_argv[0]} == --apptainer ]] || {
  printf '%s\n' 'Apptainer-only status selected the wrong backend' >&2; exit 1;
}
apptainer_status_evidence=
for ((index = 0; index < ${#apptainer_status_argv[@]} - 1; index++)); do
  if [[ ${apptainer_status_argv[index]} == --host-evidence-v1 ]]; then
    apptainer_status_evidence=${apptainer_status_argv[index + 1]}
    break
  fi
done
python3 - "$apptainer_status_evidence" <<'PY'
import base64
import json
import sys

payload = json.loads(base64.urlsafe_b64decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 4)))
assert payload["container_runtime"]["state"] == "present"
assert payload["container_runtime"]["family"] == "apptainer"
PY
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  CT_ROOT="$alternate_link" "$installed_wrapper" start --json
apptainer_server_status=$?
set -e
[[ $apptainer_server_status -eq 23 ]] || {
  printf '%s\n' 'Apptainer-only server launch did not reach the persistent executor' >&2; exit 1;
}
mapfile -t apptainer_server_argv < "$runtime_log"
[[ ${apptainer_server_argv[0]} == --apptainer ]] || {
  printf '%s\n' 'Apptainer-only server launch selected the wrong backend' >&2; exit 1;
}
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  CT_ROOT="$alternate_link" "$installed_mkchad" 'apptainer file'
apptainer_editor_status=$?
set -e
[[ $apptainer_editor_status -eq 23 ]] || {
  printf '%s\n' 'Apptainer-only MkChad launch did not reach the persistent executor' >&2; exit 1;
}
mapfile -t apptainer_editor_argv < "$runtime_log"
[[ ${apptainer_editor_argv[0]} == --apptainer ]] || {
  printf '%s\n' 'Apptainer-only MkChad launch selected the wrong backend' >&2; exit 1;
}
mv "$fake/singularity.disabled" "$fake/singularity"

missing_state="$work/missing state"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER "${base_env[@]}" \
  "XDG_STATE_HOME=$missing_state" "$installed_wrapper" status --json >"$work/missing-state.out" 2>"$work/missing-state.err"
missing_state_status=$?
set -e
[[ $missing_state_status -eq 19 && ! -e $missing_state ]] || {
  printf '%s\n' 'status created or required a missing external state root' >&2; exit 1;
}
mapfile -t status_with_npm < "$status_log"
npm_bind=0
npm_env=0
for ((index = 0; index < ${#status_with_npm[@]}; index++)); do
  [[ ${status_with_npm[index]} != "$home/.local/share/msk_containers/npm-global:/opt/msk/npm-global:ro" ]] || npm_bind=1
  [[ ${status_with_npm[index]} != MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global ]] || npm_env=1
done
[[ $npm_bind == 1 && $npm_env == 1 ]] || {
  printf '%s\n' 'status did not expose the existing npm prefix read-only' >&2; exit 1;
}

rm "$runtime_log"
set +e
env "${base_env[@]}" \
  SINGULARITY_CONTAINER="$image" \
  MKCHAD_NVIM_IMAGE=1 \
  XDG_RUNTIME_DIR="$work/image-runtime" XDG_CACHE_HOME="$work/image-cache" \
  MSK_NPM_GLOBAL_BASE=/opt/msk/npm-global \
  MSK_NPM_GLOBAL_ROOT=/opt/msk/npm-global/linux-x64-node24 \
  NPM_CONFIG_PREFIX=/opt/msk/npm-global/linux-x64-node24 \
  OPENCODE_CONFIG="$config/mkchad/opencode.jsonc" \
  PATH="/opt/msk/npm-global/linux-x64-node24/bin:$fake:$PATH" \
  "$installed_image_command" status --json
container_status=$?
set -e
[[ $container_status -eq 19 ]] || { printf '%s\n' 'in-container invocation did not call image nvim directly' >&2; exit 1; }
[[ ! -e $runtime_log ]] || { printf '%s\n' 'in-container invocation nested the container runtime' >&2; exit 1; }
mapfile -t nvim_argv < "$nvim_log"
[[ ${nvim_argv[0]} == -u && ${nvim_argv[1]} == NONE && ${nvim_argv[2]} == -l && ${nvim_argv[4]} == -- && ${nvim_argv[5]} == status && ${nvim_argv[6]} == --json ]] || {
  printf '%s\n' 'in-container nvim argv changed' >&2; exit 1;
}
[[ $(<"$nvim_log") == *"marker=1 home=$home state=$state_default runtime=$work/image-runtime cache=$work/image-cache data=$home/.local/share base=/opt/msk/npm-global root=/opt/msk/npm-global/linux-x64-node24 prefix=/opt/msk/npm-global/linux-x64-node24 config=$config/mkchad/opencode.jsonc log=/dev/null"* ]] || {
  printf '%s\n' 'in-container invocation did not preserve MkChad environment' >&2; exit 1;
}
[[ $(<"$nvim_log") == *"path=/opt/msk/npm-global/linux-x64-node24/bin:"* ]] || {
  printf '%s\n' 'in-container invocation did not prioritize side-installed tools' >&2; exit 1;
}

rm "$nvim_log"
set +e
env "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 "$installed_wrapper" status --json
compatibility_status=$?
set -e
[[ $compatibility_status -eq 19 && -e $nvim_log && ! -e $runtime_log ]] || {
  printf '%s\n' 'public launcher did not preserve in-container compatibility without nesting' >&2; exit 1;
}

rm "$nvim_log"
set +e
env -u MKCHAD_PERSISTENT_INSTANCE "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 \
  "$installed_wrapper" start --json >"$work/foreground-start.out" 2>"$work/foreground-start.err"
foreground_start_status=$?
set -e
[[ $foreground_start_status -eq 1 && $(<"$work/foreground-start.err") == *'detached start requires the managed persistent container instance'* \
  && ! -e $nvim_log && ! -e $runtime_log ]] || {
  printf '%s\n' 'foreground container start did not fail before lifecycle execution' >&2; exit 1;
}

set +e
env -u MKCHAD_PERSISTENT_INSTANCE "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 \
  "$installed_image_command" start --json >"$work/direct-foreground-start.out" 2>"$work/direct-foreground-start.err"
direct_foreground_start_status=$?
set -e
[[ $direct_foreground_start_status -eq 1 \
  && $(<"$work/direct-foreground-start.err") == *'detached start requires the managed persistent container instance'* \
  && ! -e $nvim_log ]] || {
  printf '%s\n' 'in-image companion allowed detached start without mount authority' >&2; exit 1;
}

set +e
env "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 MKCHAD_PERSISTENT_INSTANCE=1 \
  "$installed_image_command" start --json
managed_start_status=$?
set -e
[[ $managed_start_status -eq 19 && -e $nvim_log ]] || {
  printf '%s\n' 'managed instance marker did not authorize in-image start' >&2; exit 1;
}

mkdir -p "$work/no-runtime-tools"
cat > "$work/no-runtime-tools/dirname" <<'EOF'
#!/bin/bash
printf '%s\n' "${1%/*}"
EOF
cat > "$work/no-runtime-tools/realpath" <<'EOF'
#!/bin/bash
/usr/bin/readlink -f "$1"
EOF
chmod 755 "$work/no-runtime-tools/dirname" "$work/no-runtime-tools/realpath"
set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER -u MKCHAD_NVIM_IMAGE \
  PATH="$work/no-runtime-tools" HOME="$home" XDG_CONFIG_HOME="$config" NVIM_CONT_LOCATION="$image" \
  /bin/bash "$installed_wrapper" status --json >"$work/missing-runtime.out" 2>"$work/missing-runtime.err"
missing_runtime_status=$?
set -e
[[ $missing_runtime_status -eq 1 && $(<"$work/missing-runtime.err") == *'neither Apptainer nor SingularityCE is available'* ]] || {
  printf '%s\n' 'missing container runtime did not fail clearly' >&2; exit 1;
}

set +e
env -u SINGULARITY_CONTAINER -u APPTAINER_CONTAINER -u MKCHAD_NVIM_IMAGE \
  "${base_env[@]}" NVIM_CONT_LOCATION="$work/missing-image.sif" "$installed_wrapper" status --json >"$work/missing-image.out" 2>"$work/missing-image.err"
missing_image_status=$?
set -e
[[ $missing_image_status -eq 1 && $(<"$work/missing-image.err") == *'active Neovim image is missing'* ]] || {
  printf '%s\n' 'missing active image did not fail clearly' >&2; exit 1;
}

rm "$config/mkchad/lua/mkchad/opencode/command.lua"
set +e
env "${base_env[@]}" SINGULARITY_CONTAINER="$image" MKCHAD_NVIM_IMAGE=1 \
  "$installed_image_command" status --json >"$work/missing-assets.out" 2>"$work/missing-assets.err"
missing_assets_status=$?
set -e
[[ $missing_assets_status -eq 1 && $(<"$work/missing-assets.err") == *'installed MkChad lifecycle entrypoint is missing'* ]] || {
  printf '%s\n' 'missing lifecycle assets did not fail clearly' >&2; exit 1;
}
printf '%s\n' 'opencode server wrapper tests passed'
