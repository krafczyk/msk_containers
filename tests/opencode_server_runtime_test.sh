#!/usr/bin/env bash
#
# Opt-in evidence harness. It deliberately has no fixture success path: a
# missing runtime or prerequisite exits 77 and records no support claim.
set -euo pipefail

work=${1:?pass a new task-specific directory beneath /tmp/opencode-mkchad}
wrapper=${2:?pass the source mkchad-opencode-server wrapper path}
[[ $work == /tmp/opencode-mkchad/* ]] || { printf '%s\n' 'runtime test directory must be beneath /tmp/opencode-mkchad' >&2; exit 2; }

unavailable() {
  printf 'runtime evidence unavailable: %s\n' "$*" >&2
  exit 77
}

[[ ${MKCHAD_OPENCODE_RUNTIME_TEST:-} == 1 ]] || unavailable 'set MKCHAD_OPENCODE_RUNTIME_TEST=1 to enable real runtime checks'
if command -v apptainer >/dev/null 2>&1; then
  runtime=apptainer
elif command -v singularity >/dev/null 2>&1; then
  runtime=singularity
else
  unavailable 'neither Apptainer nor SingularityCE is available'
fi

image=${MKCHAD_OPENCODE_RUNTIME_IMAGE:-}
source_root=${MKCHAD_OPENCODE_RUNTIME_MKCHAD_SOURCE:-}
npm_source=${MKCHAD_OPENCODE_RUNTIME_NPM_BASE:-}
[[ $image == /* && -f $image ]] || unavailable 'MKCHAD_OPENCODE_RUNTIME_IMAGE must name an active absolute SIF'
[[ $source_root == /* && -d $source_root/lua && -d $source_root/java && -d $source_root/scripts ]] || \
  unavailable 'MKCHAD_OPENCODE_RUNTIME_MKCHAD_SOURCE must name the reviewed MkChad source tree'
[[ $npm_source == /* && -d $npm_source ]] || \
  unavailable 'MKCHAD_OPENCODE_RUNTIME_NPM_BASE must name the mounted npm global base'
[[ ! -e $work ]] || { printf '%s\n' 'runtime test directory already exists' >&2; exit 2; }
[[ -x $wrapper ]] || { printf '%s\n' 'wrapper is not executable' >&2; exit 2; }

# These are prerequisites of the schema-4 broker, not optional fixture skips.
"$runtime" exec "$image" java -version >/dev/null 2>&1 || unavailable 'the selected image has no usable Java runtime'
"$runtime" exec "$image" python3 --version >/dev/null 2>&1 || unavailable 'the selected image has no usable Python runtime'

json_field() {
  local file=$1
  local path=$2
  python3 - "$file" "$path" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].split("."):
    value = value[key]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("null")
else:
    print(value)
PY
}

expect_json() {
  local file=$1
  local command=$2
  local status=$3
  [[ $(json_field "$file" ok) == true \
    && $(json_field "$file" command) == "$command" \
    && $(json_field "$file" status) == "$status" ]] || {
    printf '%s\n' "unexpected $command result; inspect $file" >&2
    exit 1
  }
}

mkdir -p "$work/home/.config" "$work/evidence" "$work/hooks"
home="$work/home"
config="$home/.config"
state="$work/state root"
hook_dir="$work/hooks"
mkdir -p "$state" "$home/.local/share/msk_containers"
ln -s "$npm_source" "$home/.local/share/msk_containers/npm-global"
mkdir -p "$config/mkchad"
cp -a "$source_root/lua" "$source_root/java" "$source_root/scripts" "$config/mkchad/"
printf '%s\n' '{"tls_proxy":true}' > "$config/mkchad/opencode-server.json"
chmod 700 "$config/mkchad" "$state"
chmod 600 "$config/mkchad/opencode-server.json"

repo=${wrapper%/nvim/bin/mkchad-opencode-server}
installer="$repo/bin/install_nvim.sh"
HOME="$home" "$installer" >/dev/null
installed_wrapper="$home/.local/bin/mkchad-opencode-server"
installed_image="$home/.local/bin/mkchad-opencode-server-image"
[[ -x $installed_wrapper && -x $installed_image ]] || {
  printf '%s\n' 'installer did not produce the exact wrapper/image pair' >&2
  exit 1
}

instance_name=
instance_root="$home/.local/share/mkchad/tmp/container-instances"
cleanup() {
  local identity
  local key
  local value
  local cleanup_name
  for identity in "$instance_root"/mkchad-*.identity; do
    [[ -f $identity ]] || continue
    cleanup_name=
    while IFS='=' read -r key value; do
      [[ $key != name ]] || cleanup_name=$value
    done < "$identity"
    if [[ $cleanup_name =~ ^mkchad-[0-9a-f]{32}$ ]]; then
      "$runtime" instance stop "$cleanup_name" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

runtime_version=$("$runtime" --version 2>&1 || true)
runtime_version=${runtime_version//$'\n'/ }
runtime_version=${runtime_version:0:200}
image_revision=$(sha256sum "$image" | cut -d' ' -f1)
ptrace_policy=unavailable
[[ -r /proc/sys/kernel/yama/ptrace_scope ]] && read -r ptrace_policy < /proc/sys/kernel/yama/ptrace_scope
{
  printf 'runtime=%s\n' "$runtime"
  printf 'runtime_version=%s\n' "$runtime_version"
  printf 'image_sha256=%s\n' "$image_revision"
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'bind_policy=default-home;explicit-identical-state;npm-wrapper-managed\n'
  printf 'state_filesystem=%s\n' "$(stat -fc '%T' -- "$state")"
  printf 'java=available\npython=available\n'
  printf 'host_procfs_policy=yama_ptrace_scope:%s\n' "$ptrace_policy"
} > "$work/evidence/runtime.txt"

run_command() {
  env HOME="$home" XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$state" \
    NVIM_CONT_LOCATION="$image" JAVA_TOOL_OPTIONS="-Dmkchad.proxy.test-hook-dir=$hook_dir" \
    "$installed_wrapper" "$@"
}

host=$(hostname)
state_file="$state/mkchad/opencode/$host/state.json"
control_file="$state/mkchad/opencode/$host/control.sock"

# Each call below is a separate host invocation of the installed public wrapper.
set +e
run_command start --json > "$work/start-1.json"
initial_start_status=$?
set -e
identity_files=("$instance_root"/mkchad-*.identity)
if [[ ${#identity_files[@]} -eq 1 && -f ${identity_files[0]} ]]; then
  while IFS='=' read -r key value; do
    [[ $key != name ]] || instance_name=$value
  done < "${identity_files[0]}"
fi
[[ $initial_start_status -eq 0 ]] || { printf '%s\n' 'initial runtime start failed' >&2; exit 1; }
expect_json "$work/start-1.json" start healthy
[[ -f $state_file && -S $control_file ]] || { printf '%s\n' 'start did not publish schema-4 state and control socket' >&2; exit 1; }
identity_files=("$instance_root"/mkchad-*.identity)
[[ ${#identity_files[@]} -eq 1 && -f ${identity_files[0]} ]] || {
  printf '%s\n' 'start did not record exactly one isolated persistent instance' >&2; exit 1;
}
[[ $instance_name =~ ^mkchad-[0-9a-f]{32}$ ]] || { printf '%s\n' 'persistent instance name is invalid' >&2; exit 1; }
"$runtime" exec "instance://$instance_name" /bin/true || {
  printf '%s\n' 'persistent instance is unavailable after the start manager exited' >&2; exit 1;
}
generation=$(json_field "$work/start-1.json" state.generation)
control_inode=$(stat -c '%d:%i' -- "$control_file")
backend_pid=$(json_field "$state_file" backend.pid)
broker_pid=$(json_field "$state_file" proxy.pid)
[[ $(json_field "$state_file" schema) == 4 ]] || { printf '%s\n' 'runtime start did not use schema-4 broker state' >&2; exit 1; }
[[ $(json_field "$state_file" broker.control_ino) == "${control_inode#*:}" ]] || {
  printf '%s\n' 'published broker control inode differs from the filesystem inode' >&2; exit 1;
}

# The completed manager has exited. A fresh host caller must use brokered status
# while the same detached generation and control inode remain authoritative.
run_command status --json > "$work/status-1.json"
expect_json "$work/status-1.json" status healthy
run_command start --json > "$work/start-2.json"
expect_json "$work/start-2.json" start healthy
[[ $(json_field "$work/start-2.json" state.generation) == "$generation" \
  && $(stat -c '%d:%i' -- "$control_file") == "$control_inode" ]] || {
  printf '%s\n' 'separate host invocations did not reuse the generation and control inode' >&2; exit 1;
}
[[ ! -r /proc/$backend_pid/fd && ! -r /proc/$broker_pid/fd ]] || {
  printf '%s\n' 'protected procfs denial was not reproduced from the fresh host context' >&2; exit 1;
}
{
  printf 'generation=%s\n' "$generation"
  printf 'control_inode=%s\n' "$control_inode"
  printf 'broker_pid=%s\n' "$broker_pid"
  printf 'backend_pid=%s\n' "$backend_pid"
  printf 'instance_name=%s\n' "$instance_name"
  printf 'instance_persisted_after_manager=yes\n'
  printf 'generation_reused=yes\ncontrol_inode_stable=yes\nprocfs_denied=yes\n'
} >> "$work/evidence/runtime.txt"

# The Java test hook pauses exactly at broker-context pidfd dispatch. At that
# point public admission, accept, and relays must already be quiescent.
touch "$hook_dir/pidfd-signal.enabled"
run_command stop --json > "$work/stop-1.json" &
stop_pid=$!
for _ in $(seq 1 150); do
  [[ -e $hook_dir/pidfd-signal.reached ]] && break
  sleep 0.1
done
[[ -e $hook_dir/pidfd-signal.reached ]] || { printf '%s\n' 'broker-context pidfd hook was not reached' >&2; exit 1; }
url=$(json_field "$work/start-1.json" state.url)
ca_cert=$(json_field "$work/start-1.json" state.ca_cert)
if curl --fail --silent --show-error --max-time 2 --cacert "$ca_cert" "$url/global/health" >/dev/null 2>&1; then
  printf '%s\n' 'public admission remained reachable at broker pidfd dispatch' >&2
  exit 1
fi
touch "$hook_dir/pidfd-signal.release"
wait "$stop_pid"
expect_json "$work/stop-1.json" stop inactive
[[ ! -e $state_file && ! -e $control_file ]] || {
  printf '%s\n' 'state or control socket was removed before receipt-gated broker completion' >&2; exit 1;
}
"$runtime" exec "instance://$instance_name" /bin/true || {
  printf '%s\n' 'safe server stop unexpectedly destroyed the shared runtime instance' >&2; exit 1;
}
printf 'brokered_status=yes\npublic_quiesce_before_pidfd=yes\nreceipt_gated_cleanup=yes\ninstance_retained_after_server_stop=yes\n' >> "$work/evidence/runtime.txt"

# Recreate a generation, then exercise the documented broker/backend death
# matrix from separate host status calls. Forced kills are confined to PIDs from
# the freshly validated isolated state file.
rm -f "$hook_dir"/*
run_command start --json > "$work/start-3.json"
expect_json "$work/start-3.json" start healthy
backend_pid=$(json_field "$state_file" backend.pid)
broker_pid=$(json_field "$state_file" proxy.pid)
"$runtime" exec "instance://$instance_name" /bin/kill -KILL "$backend_pid"
run_command status --json > "$work/backend-dead.json"
[[ $(json_field "$work/backend-dead.json" status) == unhealthy ]] || {
  printf '%s\n' 'broker-live/backend-dead was not reported unhealthy' >&2; exit 1;
}
run_command stop --json > "$work/backend-dead-stop.json"
expect_json "$work/backend-dead-stop.json" stop inactive

run_command start --json > "$work/start-4.json"
expect_json "$work/start-4.json" start healthy
backend_pid=$(json_field "$state_file" backend.pid)
broker_pid=$(json_field "$state_file" proxy.pid)
"$runtime" exec "instance://$instance_name" /bin/kill -KILL "$broker_pid"
run_command status --json > "$work/broker-dead.json"
[[ $(json_field "$work/broker-dead.json" status) == blocked ]] || {
  printf '%s\n' 'broker-dead/backend-live was not reported blocked' >&2; exit 1;
}
"$runtime" exec "instance://$instance_name" /bin/kill -KILL "$backend_pid"
run_command stop --json > "$work/both-dead-stop.json"
expect_json "$work/both-dead-stop.json" stop inactive
printf 'broker_backend_death_matrix=yes\nprocesses_observed=broker,backend\n' >> "$work/evidence/runtime.txt"

printf 'runtime evidence passed: %s\n' "$work/evidence/runtime.txt"
