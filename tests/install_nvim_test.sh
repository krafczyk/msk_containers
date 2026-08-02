#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a new task-specific directory beneath /tmp/mkchad-v1}
[[ $work == /tmp/mkchad-v1/* ]] || {
  printf '%s\n' 'test directory must be beneath /tmp/mkchad-v1' >&2
  exit 2
}
[[ ! -e $work ]] || {
  printf '%s\n' 'test directory already exists' >&2
  exit 2
}

repo=$(git rev-parse --show-toplevel)
fixture="$work/fixture"
home="$work/home"
recovery="$work/recovery"
mkdir -p "$fixture" "$home" "$recovery"
chmod 700 "$recovery"
cp -a "$repo/bin" "$repo/container_tools" "$repo/nvim" "$fixture/"

installer="$fixture/bin/install_nvim.sh"
tools_installer="$fixture/bin/install_tools.sh"
target="$home/.local/bin"

# A check must validate the complete output set without creating host paths.
HOME="$home" bash "$installer" --check >/dev/null
[[ ! -e $home/.local ]] || {
  printf '%s\n' '--check created a host output directory' >&2
  exit 1
}

HOME="$home" bash "$installer" >/dev/null
[[ -x $target/nvim && -x $target/ct_exec.sh ]] || {
  printf '%s\n' 'installer did not install launchers and container tools' >&2
  exit 1
}

before=$(stat -c '%d:%i:%a' -- "$target/nvim")
HOME="$home" bash "$installer" --check >/dev/null
HOME="$home" bash "$installer" >/dev/null
[[ $(stat -c '%d:%i:%a' -- "$target/nvim") == "$before" ]] || {
  printf '%s\n' 'compliant launcher was rewritten' >&2
  exit 1
}

printf '%s\n' '# updated launcher fixture' >> "$fixture/nvim/bin/nvim"
printf '%s\n' '# updated tool fixture' >> "$fixture/container_tools/ct_exec.sh"
cp -- "$target/nvim" "$work/nvim-before"
cp -- "$target/ct_exec.sh" "$work/ct-exec-before"
HOME="$home" bash "$installer" --check >/dev/null
cmp "$work/nvim-before" "$target/nvim" || {
  printf '%s\n' '--check rewrote a noncompliant launcher' >&2
  exit 1
}
cmp "$work/ct-exec-before" "$target/ct_exec.sh" || {
  printf '%s\n' '--check rewrote a noncompliant container tool' >&2
  exit 1
}
rm "$target/mkchad-opencode-server"
mkdir "$target/mkchad-opencode-server"
set +e
late_output=$(HOME="$home" bash "$installer" --recovery-dir "$recovery" 2>&1)
late_status=$?
set -e
[[ $late_status -ne 0 && $late_output == *'non-regular output'* ]] || {
  printf '%s\n' 'late incompatible output did not block preflight' >&2
  exit 1
}
cmp "$work/nvim-before" "$target/nvim" || {
  printf '%s\n' 'late incompatible output allowed an earlier write' >&2
  exit 1
}
rmdir "$target/mkchad-opencode-server"

HOME="$home" bash "$installer" --recovery-dir "$recovery" >/dev/null
cmp "$work/nvim-before" "$recovery/nvim" || {
  printf '%s\n' 'replacement did not retain prior launcher bytes' >&2
  exit 1
}
cmp "$work/ct-exec-before" "$recovery/ct_exec.sh" || {
  printf '%s\n' 'replacement did not retain prior container-tool bytes' >&2
  exit 1
}

rm "$target/nvim_shell"
ln -s /tmp "$target/nvim_shell"
set +e
symlink_output=$(HOME="$home" bash "$installer" --check 2>&1)
symlink_status=$?
set -e
rm "$target/nvim_shell"
[[ $symlink_status -ne 0 && $symlink_output == *'symlink output'* ]] || {
  printf '%s\n' 'symlink output was not rejected' >&2
  exit 1
}

mkdir "$target/nvim_shell"
set +e
directory_output=$(HOME="$home" bash "$installer" --check 2>&1)
directory_status=$?
set -e
rmdir "$target/nvim_shell"
[[ $directory_status -ne 0 && $directory_output == *'non-regular output'* ]] || {
  printf '%s\n' 'directory output was not rejected' >&2
  exit 1
}

unsafe_home="$work/unsafe-home"
mkdir -p "$unsafe_home/.local"
chmod 777 "$unsafe_home/.local"
set +e
unsafe_output=$(HOME="$unsafe_home" bash "$installer" --check 2>&1)
unsafe_status=$?
set -e
[[ $unsafe_status -ne 0 && $unsafe_output == *'unsafe parent'* ]] || {
  printf '%s\n' 'unsafe parent was not rejected' >&2
  exit 1
}

managed_home="$work/managed-home"
managed_bin="$work/managed-bin"
mkdir -p "$managed_home/.local" "$managed_bin"
cat >"$managed_bin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ ${!#} == "$MKCHAD_TEST_MANAGED_HOME" ]]; then
  case ${2:-} in
    %u) printf '%s\n' "${MKCHAD_TEST_MANAGED_UID:-0}"; exit 0 ;;
    %a) printf '%s\n' "${MKCHAD_TEST_MANAGED_MODE:-770}"; exit 0 ;;
  esac
fi
exec "$MKCHAD_TEST_REAL_STAT" "$@"
EOF
chmod 755 "$managed_bin/stat"
real_stat=$(command -v stat)
set +e
managed_output=$(PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_REAL_STAT="$real_stat" HOME="$managed_home" bash "$installer" --check 2>&1)
managed_status=$?
set -e
[[ $managed_status -ne 0 && $managed_output == *'not current-user-owned'* ]] || {
  printf '%s\n' 'managed root was accepted without explicit trust' >&2
  exit 1
}
PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_REAL_STAT="$real_stat" \
  MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 HOME="$managed_home" bash "$installer" --check >/dev/null
PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_REAL_STAT="$real_stat" \
  MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 HOME="$managed_home" bash "$tools_installer" --check >/dev/null
set +e
managed_world_output=$(PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_MANAGED_MODE=777 \
  MKCHAD_TEST_REAL_STAT="$real_stat" MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 HOME="$managed_home" bash "$installer" --check 2>&1)
managed_world_status=$?
set -e
[[ $managed_world_status -ne 0 && $managed_world_output == *'group- or world-writable'* ]] || {
  printf '%s\n' 'managed world-writable root was not rejected' >&2
  exit 1
}
set +e
managed_foreign_output=$(PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_MANAGED_UID=1234 \
  MKCHAD_TEST_REAL_STAT="$real_stat" MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 HOME="$managed_home" bash "$installer" --check 2>&1)
managed_foreign_status=$?
set -e
[[ $managed_foreign_status -ne 0 && $managed_foreign_output == *'not root- or current-user-owned'* ]] || {
  printf '%s\n' 'managed foreign-owned root was not rejected' >&2
  exit 1
}
chmod 777 "$managed_home/.local"
set +e
managed_descendant_output=$(PATH="$managed_bin:$PATH" MKCHAD_TEST_MANAGED_HOME="$managed_home" MKCHAD_TEST_REAL_STAT="$real_stat" \
  MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 HOME="$managed_home" bash "$tools_installer" --check 2>&1)
managed_descendant_status=$?
set -e
chmod 755 "$managed_home/.local"
[[ $managed_descendant_status -ne 0 && $managed_descendant_output == *'group- or world-writable'* ]] || {
  printf '%s\n' 'unsafe managed-root descendant was not rejected' >&2
  exit 1
}

foreign="$target/nvim_clear_data"
if chown 1:1 "$foreign" 2>/dev/null; then
  set +e
  foreign_output=$(HOME="$home" bash "$installer" --check 2>&1)
  foreign_status=$?
  set -e
  chown "$(id -u):$(id -g)" "$foreign"
  [[ $foreign_status -ne 0 && $foreign_output == *'foreign-owned output'* ]] || {
    printf '%s\n' 'foreign-owned output was not rejected' >&2
    exit 1
  }
else
  printf '%s\n' 'foreign-owner assertion skipped: chown is unavailable to this user'
fi

printf '%s\n' '# concurrent fixture update' >> "$fixture/nvim/bin/nvim"
cp -- "$target/nvim" "$work/nvim-before-concurrent"
mkdir "$work/recovery-concurrent"
chmod 700 "$work/recovery-concurrent"
lock="$target/.install_nvim.lock"
(
  exec 9>>"$lock"
  flock -x 9
  sleep 2
) &
lock_holder=$!
HOME="$home" bash "$installer" --recovery-dir "$work/recovery-concurrent" >"$work/concurrent.out" 2>&1 &
installer_pid=$!
sleep 0.2
cmp "$target/nvim" "$work/nvim-before-concurrent" || {
  printf '%s\n' 'concurrent installer wrote before acquiring the shared lock' >&2
  exit 1
}
[[ -d "/proc/$installer_pid" ]] || {
  printf '%s\n' 'concurrent installer did not wait for the shared lock' >&2
  exit 1
}
wait "$lock_holder"
wait "$installer_pid"

printf '%s\n' '# interruption fixture update' >> "$fixture/nvim/bin/nvim"
cp -- "$target/nvim" "$work/nvim-before-interruption"
mkdir "$work/recovery-interruption"
chmod 700 "$work/recovery-interruption"
HOME="$home" MSK_INSTALL_TEST_PAUSE_AFTER_REPLACE=nvim \
  bash "$installer" --recovery-dir "$work/recovery-interruption" >"$work/interrupted.out" 2>&1 &
interrupted_pid=$!
for _ in {1..100}; do
  cmp -s "$fixture/nvim/bin/nvim" "$target/nvim" && break
  sleep 0.05
done
kill -KILL "$interrupted_pid" 2>/dev/null || true
wait "$interrupted_pid" 2>/dev/null || true
cmp "$fixture/nvim/bin/nvim" "$target/nvim" || {
  printf '%s\n' 'interrupted replacement did not leave known new bytes' >&2
  exit 1
}
cmp "$work/nvim-before-interruption" "$work/recovery-interruption/nvim" || {
  printf '%s\n' 'interrupted replacement did not retain recovery bytes' >&2
  exit 1
}

printf '%s\n' 'install_nvim tests passed'
