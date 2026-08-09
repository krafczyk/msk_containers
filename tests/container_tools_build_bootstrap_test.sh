#!/usr/bin/env bash
# Exercise container-image build tool resolution without invoking image backends.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
resolver="$repo/nvim/bin/resolve_container_tools.sh"
work=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/build-bootstrap-test.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

git_path=$(command -v git)
cmake_path=$(command -v cmake)
flock_path=$(command -v flock)
cc_path=$(command -v cc)
compiler=${CC:-cc}
compiler_path=$(command -v "$compiler")
compiler_name=${compiler##*/}
uname_path=$(command -v uname)
timeout_path=$(command -v timeout)
dirname_path=$(command -v dirname)
realpath_path=$(command -v realpath)
bash_path=$(command -v bash)
make_path=$(command -v make)
ar_path=$(command -v ar)
ranlib_path=$(command -v ranlib)
sleep_path=$(command -v sleep)
mkdir_path=$(command -v mkdir)
mktemp_path=$(command -v mktemp)
rm_path=$(command -v rm)
mv_path=$(command -v mv)
cp_path=$(command -v cp)
base_bin="$work/base-bin"
mkdir -p -- "$base_bin"
ln -s "$git_path" "$base_bin/git"
ln -s "$cmake_path" "$base_bin/cmake"
ln -s "$flock_path" "$base_bin/flock"
ln -s "$cc_path" "$base_bin/cc"
ln -s "$uname_path" "$base_bin/uname"
ln -s "$timeout_path" "$base_bin/timeout"
ln -s "$dirname_path" "$base_bin/dirname"
ln -s "$realpath_path" "$base_bin/realpath"
ln -s "$bash_path" "$base_bin/bash"
ln -s "$make_path" "$base_bin/make"
ln -s "$ar_path" "$base_bin/ar"
ln -s "$ranlib_path" "$base_bin/ranlib"
ln -s "$sleep_path" "$base_bin/sleep"
ln -s "$mkdir_path" "$base_bin/mkdir"
ln -s "$mktemp_path" "$base_bin/mktemp"
ln -s "$rm_path" "$base_bin/rm"
ln -s "$mv_path" "$base_bin/mv"
ln -s "$cp_path" "$base_bin/cp"
if [[ $compiler_name != cc ]]; then
  ln -s "$compiler_path" "$base_bin/$compiler_name"
fi
base_path=$base_bin
gitlink=$("$git_path" -C "$repo" ls-tree HEAD -- container_tools)
gitlink=${gitlink%$'\t'container_tools}
[[ $gitlink =~ ^160000\ commit\ ([0-9a-f]{40})$ ]] || {
  printf '%s\n' 'parent repository does not record a container_tools gitlink' >&2
  exit 1
}
source_commit=${BASH_REMATCH[1]}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

native_architecture=$("$uname_path" -m)
case $native_architecture in
  x86_64 | amd64)
    native_architecture=x86_64
    alternate_architecture=aarch64
    ;;
  aarch64 | arm64)
    native_architecture=aarch64
    alternate_architecture=ppc64le
    ;;
  ppc64le)
    native_architecture=ppc64le
    alternate_architecture=x86_64
    ;;
  *) fail "unsupported test host architecture: $native_architecture" ;;
esac

assert_contains() {
  local file=$1 expected=$2

  grep -Fq -- "$expected" "$file" || fail "missing $expected in $file"
}

assert_post_lock_key_recomputation() {
  local -a source_checks prefix_lines
  local post_lock_source_line prefix_line

  mapfile -t source_checks < <(grep -n '^  require_bootstrap_source$' "$resolver")
  (( ${#source_checks[@]} == 2 )) || fail 'resolver does not recheck the source after acquiring its lock'
  post_lock_source_line=${source_checks[1]%%:*}
  local prefix_pattern="^  prefix=\"\\\$architecture_root/\\\$source_commit\"$"

  mapfile -t prefix_lines < <(grep -n "$prefix_pattern" "$resolver")
  (( ${#prefix_lines[@]} == 2 )) || fail 'resolver does not derive the bootstrap prefix before and after locking'
  prefix_line=${prefix_lines[1]}
  prefix_line=${prefix_line%%:*}
  (( prefix_line > post_lock_source_line )) ||
    fail 'resolver does not recompute the source-keyed prefix after its post-lock source recheck'
}

assert_post_lock_key_recomputation

make_package() {
  local root=$1
  mkdir -p -- "$root"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "[[ \${1:-} == package && \${2:-} == verify ]]" > "$root/container-tools"
  chmod +x -- "$root/container-tools"
  printf '%s' "$root"
}

make_identity_package() {
  local root=$1 architecture=$2 commit=$3

  mkdir -p -- "$root"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "[[ \${1:-} == package && \${2:-} == verify ]] || exit 1" \
    "printf '%s\\n' '{\"architecture\":\"$architecture\",\"source_commit\":\"$commit\"}'" > "$root/container-tools"
  chmod +x -- "$root/container-tools"
}

expect_failure() {
  local expected=$1
  shift
  local output
  if output=$("$@" 2>&1); then
    fail "resolver unexpectedly succeeded: $*"
  fi
  [[ $output == *"$expected"* ]] || fail "resolver failure did not contain $expected: $output"
}

wait_for_file() {
  local path=$1 description=$2 limit=${3:-100} attempt

  for ((attempt = 0; attempt < limit; ++attempt)); do
    [[ -e $path ]] && return
    sleep 0.1
  done
  fail "timed out waiting for $description"
}

wait_for_lines() {
  local path=$1 expected=$2 description=$3 attempt lines

  for ((attempt = 0; attempt < 100; ++attempt)); do
    lines=0
    [[ ! -f $path ]] || lines=$(wc -l < "$path")
    (( lines >= expected )) && return
    sleep 0.1
  done
  fail "timed out waiting for $description"
}

assert_no_stages() {
  local root=$1
  local -a stages

  shopt -s nullglob
  stages=("$root/$native_architecture/.source-${source_commit}."* "$root/$native_architecture/.next-${source_commit}."*)
  shopt -u nullglob
  (( ${#stages[@]} == 0 )) || fail 'bootstrap retained an interrupted private stage'
}

explicit=$(make_package "$work/explicit/bin")
path_package=$(make_package "$work/path/bin")
invalid="$work/invalid/bin"
mkdir -p -- "$invalid"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$invalid/container-tools"
chmod +x -- "$invalid/container-tools"

resolved=$(CT_ROOT="$explicit" PATH="$work/path/bin:$base_path" "$resolver")
[[ $resolved == "$explicit/container-tools" ]] || fail 'CT_ROOT did not take precedence'
expect_failure 'CT_ROOT package is not complete' env CT_ROOT="$invalid" PATH="$base_path" "$resolver"

resolved=$(env -u CT_ROOT PATH="$path_package:$base_path" "$resolver")
[[ $resolved == "$path_package/container-tools" ]] || fail 'PATH package was not selected'
expect_failure 'PATH package is not complete' env -u CT_ROOT PATH="$invalid:$base_path" "$resolver"
expect_failure 'must be beneath' env -u CT_ROOT PATH="$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT=/tmp/container-tools-bootstrap-outside "$resolver"
expect_failure 'must be absolute' env -u CT_ROOT PATH="$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT=relative-bootstrap "$resolver"

lock_timeout_root="$work/lock-timeout"
mkdir -p -- "$work/timeout-flock"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '[[ $1 == -w && $2 == 3600 && $3 == 9 ]] || exit 97' \
  'exit 1' > "$work/timeout-flock/flock"
chmod +x -- "$work/timeout-flock/flock"
expect_failure 'bootstrap lock timed out' env -u CT_ROOT PATH="$work/timeout-flock:$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$lock_timeout_root" "$resolver"

failed_root="$work/failed-build"
mkdir -p -- "$work/failing-cmake"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" failing-cmake >&2' 'exit 99' > "$work/failing-cmake/cmake"
chmod +x -- "$work/failing-cmake/cmake"
expect_failure failing-cmake env -u CT_ROOT PATH="$work/failing-cmake:$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$failed_root" "$resolver"
assert_no_stages "$failed_root"

bootstrap_root="$work/bootstrap"
mkdir -p \
  "$bootstrap_root/$native_architecture/.source-${source_commit}.interrupted" \
  "$bootstrap_root/$native_architecture/.next-${source_commit}.interrupted"
resolved=$(env -u CT_ROOT PATH="$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$bootstrap_root" "$resolver")
expected="$bootstrap_root/$native_architecture/$source_commit/bin/container-tools"
[[ $resolved == "$expected" && -x $resolved ]] || fail 'absent PATH did not build a bootstrap package'
verify_json=$("$resolved" package verify --json)
[[ $verify_json == *"\"architecture\":\"$native_architecture\""* &&
   $verify_json == *"\"source_commit\":\"$source_commit\""* ]] ||
  fail 'bootstrap package did not report the expected architecture and gitlink commit'
assert_no_stages "$bootstrap_root"

mkdir -p -- "$work/broken-cmake"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" broken-cmake >&2' 'exit 99' > "$work/broken-cmake/cmake"
chmod +x -- "$work/broken-cmake/cmake"
resolved=$(env -u CT_ROOT PATH="$work/broken-cmake:$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$bootstrap_root" "$resolver")
[[ $resolved == "$expected" ]] || fail 'verified bootstrap prefix was not reused'

rm -rf -- "${bootstrap_root:?}/$native_architecture/$source_commit"
wrong_source=0000000000000000000000000000000000000000
make_identity_package "$bootstrap_root/$native_architecture/$source_commit/bin" "$alternate_architecture" "$wrong_source"
expect_failure broken-cmake env -u CT_ROOT PATH="$work/broken-cmake:$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$bootstrap_root" "$resolver"
[[ ! -e $bootstrap_root/$native_architecture/$source_commit ]] ||
  fail 'bootstrap reused a cache package with the wrong architecture or source commit'
assert_no_stages "$bootstrap_root"
resolved=$(env -u CT_ROOT PATH="$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$bootstrap_root" "$resolver")
[[ $resolved == "$expected" ]] || fail 'rejected bootstrap prefix was not rebuilt'

publication_root="$work/publication-failure"
publication_bin="$work/publication-bin"
mkdir -p -- "$publication_bin"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ ${1:-} == --install ]]; then' \
  '  while (($#)); do' \
  '    if [[ $1 == --prefix && $# -ge 2 ]]; then prefix=$2; break; fi' \
  '    shift' \
  '  done' \
  '  [[ -n ${prefix:-} ]] || exit 64' \
  '  cp -a -- "$TEST_BOOTSTRAP_PACKAGE/." "$prefix"' \
  'fi' > "$publication_bin/cmake"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" publication-failure >&2' 'exit 99' > "$publication_bin/mv"
chmod +x -- "$publication_bin/cmake" "$publication_bin/mv"
expect_failure publication-failure env -u CT_ROOT PATH="$publication_bin:$base_path" \
  TEST_BOOTSTRAP_PACKAGE="${expected%/bin/container-tools}" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$publication_root" "$resolver"
[[ ! -e $publication_root/$native_architecture/$source_commit ]] ||
  fail 'failed publication exposed a final bootstrap prefix'
assert_no_stages "$publication_root"

mkdir -p -- "$work/alternate-architecture"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' '$alternate_architecture'" > "$work/alternate-architecture/uname"
chmod +x -- "$work/alternate-architecture/uname"
alternate_expected="$bootstrap_root/$alternate_architecture/$source_commit/bin/container-tools"
resolved=$(env -u CT_ROOT PATH="$work/alternate-architecture:$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$bootstrap_root" "$resolver")
[[ $resolved == "$alternate_expected" && -x $resolved ]] || fail 'alternate architecture bootstrap did not use a separate content-addressed prefix'
[[ -x $expected && -x $alternate_expected && $expected != "$alternate_expected" ]] ||
  fail 'native architectures did not retain separate bootstrap packages'
[[ -f $bootstrap_root/$native_architecture/.bootstrap.lock && -f $bootstrap_root/$alternate_architecture/.bootstrap.lock ]] ||
  fail 'native architectures did not retain separate bootstrap locks'

mkdir -p -- "$work/unsupported"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" riscv64' > "$work/unsupported/uname"
chmod +x -- "$work/unsupported/uname"
expect_failure 'does not support native architecture: riscv64' env -u CT_ROOT PATH="$work/unsupported:$base_path" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/unsupported-bootstrap" "$resolver"

concurrent_root="$work/concurrent"
concurrent_bin="$work/concurrent-bin"
ready="$work/configure-ready"
release="$work/configure-release"
cmake_log="$work/cmake.log"
cmake_arguments="$work/cmake-arguments.log"
flock_log="$work/flock.log"
mkdir -p -- "$concurrent_bin"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\ncase ${1:-} in\n  -S) phase=configure ;;\n  --build) phase=build ;;\n  --install) phase=install ;;\n  *) phase=unexpected ;;\nesac\nprintf "%%s\\n" "$phase" >> "$CONTAINER_TOOLS_BOOTSTRAP_CMAKE_LOG"\nprintf "%%s\\n" "$*" >> "$CONTAINER_TOOLS_BOOTSTRAP_CMAKE_ARGUMENTS"\nif [[ $phase == configure ]]; then\n  : > "$CONTAINER_TOOLS_BOOTSTRAP_READY"\n  for ((attempt = 0; attempt < 100; ++attempt)); do\n    [[ -e $CONTAINER_TOOLS_BOOTSTRAP_RELEASE ]] && break\n    sleep 0.1\n  done\n  [[ -e $CONTAINER_TOOLS_BOOTSTRAP_RELEASE ]] || exit 124\nfi\nexec %q "$@"\n' "$cmake_path" > "$concurrent_bin/cmake"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" attempt >> "$CONTAINER_TOOLS_BOOTSTRAP_FLOCK_LOG"\nexec %q "$@"\n' "$flock_path" > "$concurrent_bin/flock"
chmod +x -- "$concurrent_bin/cmake" "$concurrent_bin/flock"
(
  set +e
  CONTAINER_TOOLS_BOOTSTRAP_CMAKE_LOG="$cmake_log" CONTAINER_TOOLS_BOOTSTRAP_CMAKE_ARGUMENTS="$cmake_arguments" CONTAINER_TOOLS_BOOTSTRAP_FLOCK_LOG="$flock_log" \
    CONTAINER_TOOLS_BOOTSTRAP_READY="$ready" CONTAINER_TOOLS_BOOTSTRAP_RELEASE="$release" \
    PATH="$concurrent_bin:$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$concurrent_root" "$resolver" > "$work/first.out"
  status=$?
  printf '%s\n' "$status" > "$work/first.status"
  exit "$status"
) &
first=$!
wait_for_file "$ready" 'the first configure invocation'
(
  set +e
  CONTAINER_TOOLS_BOOTSTRAP_CMAKE_LOG="$cmake_log" CONTAINER_TOOLS_BOOTSTRAP_CMAKE_ARGUMENTS="$cmake_arguments" CONTAINER_TOOLS_BOOTSTRAP_FLOCK_LOG="$flock_log" \
    CONTAINER_TOOLS_BOOTSTRAP_READY="$ready" CONTAINER_TOOLS_BOOTSTRAP_RELEASE="$release" \
    PATH="$concurrent_bin:$base_path" CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$concurrent_root" "$resolver" > "$work/second.out"
  status=$?
  printf '%s\n' "$status" > "$work/second.status"
  exit "$status"
) &
second=$!
wait_for_lines "$flock_log" 2 'the second lock attempt'
: > "$release"
wait_for_file "$work/first.status" 'the first resolver completion' 6000
wait_for_file "$work/second.status" 'the second resolver completion' 6000
wait "$first"
wait "$second"
[[ $(<"$work/first.status") == 0 && $(<"$work/second.status") == 0 ]] || fail 'concurrent bootstrap resolver failed'
[[ $(<"$work/first.out") == "$concurrent_root/$native_architecture/$source_commit/bin/container-tools" ]] || fail 'first concurrent resolution returned the wrong path'
[[ $(<"$work/second.out") == "$concurrent_root/$native_architecture/$source_commit/bin/container-tools" ]] || fail 'second concurrent resolution returned the wrong path'
[[ $(wc -l < "$flock_log") == 2 ]] || fail 'concurrent bootstrap did not make exactly two lock attempts'
[[ $(<"$cmake_log") == $'configure\nbuild\ninstall' ]] || fail 'concurrent bootstrap ran more than one configure/build/install sequence'
assert_contains "$cmake_arguments" '-DCONTAINER_TOOLS_STATIC=OFF'
# shellcheck disable=SC2016
assert_contains "$resolver" '"$timeout_command" --kill-after=10 1800 "$cmake_command" --build'

minimal="$work/minimal"
mkdir -p -- "$minimal"
ln -s "$dirname_path" "$minimal/dirname"
ln -s "$realpath_path" "$minimal/realpath"
expect_failure 'missing prerequisite: timeout' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-timeout" /bin/bash "$resolver"
ln -s "$timeout_path" "$minimal/timeout"
expect_failure 'missing prerequisite: git' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-git" /bin/bash "$resolver"
ln -s "$git_path" "$minimal/git"
expect_failure 'missing prerequisite: uname' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-uname" /bin/bash "$resolver"
ln -s "$uname_path" "$minimal/uname"
expect_failure 'missing prerequisite: cmake' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-cmake" /bin/bash "$resolver"
ln -s "$cmake_path" "$minimal/cmake"
expect_failure 'missing prerequisite: C compiler' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-cc" /bin/bash "$resolver"
ln -s "$cc_path" "$minimal/cc"
if [[ $compiler_name != cc ]]; then
  ln -s "$compiler_path" "$minimal/$compiler_name"
fi
expect_failure 'missing prerequisite: flock' env -u CT_ROOT PATH="$minimal" \
  CT_CONTAINER_TOOLS_BOOTSTRAP_ROOT="$work/missing-flock" /bin/bash "$resolver"

printf '%s\n' 'container-tools build bootstrap tests passed'
