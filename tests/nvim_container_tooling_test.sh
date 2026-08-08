#!/usr/bin/env bash
# Assertions intentionally match literal Dockerfile shell expressions.
# shellcheck disable=SC2016
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
adr="$repo/docs/adr/002-package-selections.md"
container_tools_test_root=${CONTAINER_TOOLS_TEST_CT_ROOT:?pass a complete U8 package bin directory through CONTAINER_TOOLS_TEST_CT_ROOT}
[[ $container_tools_test_root == /* && -f $container_tools_test_root/container-tools && -x $container_tools_test_root/container-tools ]] || {
  printf '%s\n' 'CONTAINER_TOOLS_TEST_CT_ROOT must name a package bin directory with container-tools' >&2
  exit 2
}
package_archive=${CONTAINER_TOOLS_PACKAGE_ARCHIVE_X86_64:?pass the verified x86_64 package archive}
package_sha256=${CONTAINER_TOOLS_PACKAGE_SHA256_X86_64:?pass the verified x86_64 package SHA-256}
package_version=${CONTAINER_TOOLS_PACKAGE_VERSION_X86_64:?pass the verified x86_64 package version}
package_commit=${CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT_X86_64:?pass the verified x86_64 package source commit}
package_libc=${CONTAINER_TOOLS_PACKAGE_LIBC_X86_64:?pass the verified x86_64 package libc}
test_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/nvim-container-tooling-test.XXXXXX")
trap 'rm -rf -- "$test_tmpdir"' EXIT

assert_contains() {
  local file=$1
  local expected=$2

  grep -Fq -- "$expected" "$file" || {
    printf 'missing %q in %s\n' "$expected" "$file" >&2
    exit 1
  }
}

assert_active() {
  local file=$1
  local expected=$2
  local line
  local trimmed

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == \#* ]] && continue
    line=${line%%[[:space:]]#*}
    if [[ $line == *"$expected"* ]]; then
      return
    fi
  done < "$file"

  printf 'missing active %q in %s\n' "$expected" "$file" >&2
  exit 1
}

assert_not_contains() {
  local file=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" "$file"; then
    printf 'unexpected %q in %s\n' "$unexpected" "$file" >&2
    exit 1
  fi
}

assert_not_contains_case_insensitive() {
  local file=$1
  local unexpected=$2
  local line
  local trimmed

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == \#* ]] && continue
    line=${line%%[[:space:]]#*}
    if [[ ${line,,} == *"${unexpected,,}"* ]]; then
      printf 'unexpected active case-insensitive %q in %s\n' "$unexpected" "$file" >&2
      exit 1
    fi
  done < "$file"
}

assert_no_ct_library_sources() {
  local script

  for script in \
    "$repo"/nvim/{x86,aarch64,ppc64le}/nvim_container_*_build_{docker,singularity}.sh; do
    assert_not_contains "$script" 'ct_library.sh'
  done
}

assert_native_build_commands() {
  local architecture native_architecture docker_script singularity_script

  for architecture in x86 aarch64 ppc64le; do
    case $architecture in
      x86) native_architecture=x86_64 ;;
      aarch64) native_architecture=aarch64 ;;
      ppc64le) native_architecture=ppc64le ;;
    esac
    docker_script="$repo/nvim/$architecture/nvim_container_${architecture}_build_docker.sh"
    singularity_script="$repo/nvim/$architecture/nvim_container_${architecture}_build_singularity.sh"
    assert_contains "$docker_script" "\"\$container_tools\" buildx exec --architecture $native_architecture -- docker buildx build"
    assert_contains "$singularity_script" '"$container_tools" runtime exec --backend "${SINGULARITY##*/}" -- "$SINGULARITY" build'
    assert_contains "$docker_script" "stage_container_tools_package.sh\" $native_architecture \"\$context\""
    assert_contains "$singularity_script" "stage_container_tools_package.sh\" $native_architecture \"\$context\""
    assert_contains "$docker_script" 'CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT='
  done
}

assert_x86_package_staging() {
  local context="$test_tmpdir/x86-package-context"

  mkdir "$context" "$test_tmpdir/rejected-context"
  CONTAINER_TOOLS_PACKAGE_ARCHIVE_X86_64=$package_archive \
    CONTAINER_TOOLS_PACKAGE_SHA256_X86_64=$package_sha256 \
    CONTAINER_TOOLS_PACKAGE_VERSION_X86_64=$package_version \
    CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT_X86_64=$package_commit \
    CONTAINER_TOOLS_PACKAGE_LIBC_X86_64=$package_libc \
    "$repo/nvim/bin/stage_container_tools_package.sh" x86_64 "$context"
  cmp "$package_archive" "$context/container-tools-package.tar.gz"
  [[ $(<"$context/container-tools-package.sha256") == "$package_sha256" ]] || exit 1
  if CONTAINER_TOOLS_PACKAGE_ARCHIVE_X86_64=$package_archive \
    CONTAINER_TOOLS_PACKAGE_SHA256_X86_64=$package_sha256 \
    CONTAINER_TOOLS_PACKAGE_VERSION_X86_64=$package_version \
    CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT_X86_64=0000000000000000000000000000000000000000 \
    CONTAINER_TOOLS_PACKAGE_LIBC_X86_64=$package_libc \
    "$repo/nvim/bin/stage_container_tools_package.sh" x86_64 "$test_tmpdir/rejected-context" >/dev/null 2>&1; then
    printf '%s\n' 'package staging accepted a source-commit mismatch' >&2
    exit 1
  fi
  if CONTAINER_TOOLS_PACKAGE_ARCHIVE_X86_64=$package_archive \
    CONTAINER_TOOLS_PACKAGE_SHA256_X86_64=0000000000000000000000000000000000000000000000000000000000000000 \
    CONTAINER_TOOLS_PACKAGE_VERSION_X86_64=$package_version \
    CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT_X86_64=$package_commit \
    CONTAINER_TOOLS_PACKAGE_LIBC_X86_64=$package_libc \
    "$repo/nvim/bin/stage_container_tools_package.sh" x86_64 "$test_tmpdir/rejected-context" >/dev/null 2>&1; then
    printf '%s\n' 'package staging accepted a checksum mismatch' >&2
    exit 1
  fi
}

assert_active_before() {
  local file=$1
  local first=$2
  local second=$3
  local line
  local trimmed
  local found_first=false

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == \#* ]] && continue
    line=${line%%[[:space:]]#*}
    if [[ $found_first == false && $line == *"$first"* ]]; then
      found_first=true
      continue
    fi
    if [[ $line == *"$second"* ]]; then
      if [[ $found_first == true ]]; then
        return
      fi
      printf 'found active %q before required %q in %s\n' "$second" "$first" "$file" >&2
      exit 1
    fi
  done < "$file"

  printf 'missing active ordering %q before %q in %s\n' "$first" "$second" "$file" >&2
  exit 1
}

command_arguments() {
  local file=$1
  local marker=$2
  local line
  local reading=false

  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $reading == false ]]; then
      [[ $line == *"$marker"* ]] || continue
      reading=true
      line=${line#*"$marker"}
    fi

    local command_complete=false
    if [[ $line == *'&&'* ]]; then
      command_complete=true
      line=${line%%&&*}
    fi
    local continued=false
    [[ $line == *\\ ]] && continued=true
    line=${line%\\}

    local package
    for package in $line; do
      printf '%s\n' "$package"
    done

    if [[ $command_complete == true || $continued == false ]]; then
      return
    fi
  done < "$file"
}

dnf_has_package() {
  local file=$1
  local package=$2
  local argument

  while IFS= read -r argument; do
    [[ $argument == "$package" ]] && return 0
  done < <(command_arguments "$file" 'dnf install -y ')

  return 1
}

assert_dnf_package() {
  local file=$1
  local package=$2

  dnf_has_package "$file" "$package" || {
    printf 'missing DNF install operand %q in %s\n' "$package" "$file" >&2
    exit 1
  }
}

assert_same_arguments() {
  local marker=$1
  local description=$2
  local -a x86_arguments
  local -a arm_arguments

  mapfile -t x86_arguments < <(command_arguments "$x86" "$marker" | LC_ALL=C sort -u)
  mapfile -t arm_arguments < <(command_arguments "$arm" "$marker" | LC_ALL=C sort -u)
  if (( ${#x86_arguments[@]} == 0 || ${#arm_arguments[@]} == 0 )); then
    printf 'failed to read x86 or aarch64 %s selections\n' "$description" >&2
    exit 1
  fi
  if [[ ${x86_arguments[*]} != "${arm_arguments[*]}" ]]; then
    printf 'x86 and aarch64 %s selections differ\n' "$description" >&2
    comm -3 \
      <(printf '%s\n' "${x86_arguments[@]}") \
      <(printf '%s\n' "${arm_arguments[@]}") >&2
    exit 1
  fi
}

assert_contains_once() {
  local file=$1
  local expected=$2
  local description=$3
  local content
  local remainder

  content=$(<"$file")
  remainder=${content#*"$expected"}
  if [[ $remainder == "$content" || $remainder == *"$expected"* ]]; then
    printf '%s must contain exactly one expected %s block\n' "$file" "$description" >&2
    exit 1
  fi
}

assert_active_once() {
  local file=$1
  local expected=$2
  local description=$3
  local line
  local trimmed
  local count=0

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == \#* ]] && continue
    line=${line%%[[:space:]]#*}
    if [[ $line == *"$expected"* ]]; then
      ((count += 1))
    fi
  done < "$file"

  if (( count != 1 )); then
    printf '%s must contain exactly one active %s\n' "$file" "$description" >&2
    exit 1
  fi
}

assert_only_proot_make_target() {
  local file=$1
  local line
  local trimmed
  local count=0

  while IFS= read -r line || [[ -n $line ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ $trimmed == \#* ]] && continue
    line=${line%%[[:space:]]#*}
    [[ $line == *'make -C /tmp/proot/src '* ]] || continue
    ((count += 1))
    if [[ $line != *'make -C /tmp/proot/src proot;'* ]]; then
      printf 'unexpected PRoot make target in %s: %s\n' "$file" "$line" >&2
      exit 1
    fi
  done < "$file"

  if (( count != 1 )); then
    printf '%s must invoke exactly one PRoot make target\n' "$file" >&2
    exit 1
  fi
}

normalized_dockerfile() {
  local file=$1
  local luals_build=$2
  local content

  content=$(<"$file")
  content=${content/"$luals_build"/__ARCHITECTURE_SPECIFIC_LUALS_BUILD__}
  content=${content//bun-linux-x64/bun-linux-CONTAINER_ARCH}
  content=${content//bun-linux-aarch64/bun-linux-CONTAINER_ARCH}
  content=${content//linux-x64/linux-CONTAINER_ARCH}
  content=${content//linux-arm64/linux-CONTAINER_ARCH}
  content=${content//x86_64/CONTAINER_ARCH}
  content=${content//aarch64/CONTAINER_ARCH}
  content=${content//"$x86_opencode_sha256"/OPENCODE-CONTAINER-SHA256}
  content=${content//"$arm_opencode_sha256"/OPENCODE-CONTAINER-SHA256}
  content=${content//"$x86_bun_sha256"/BUN-CONTAINER-SHA256}
  content=${content//"$arm_bun_sha256"/BUN-CONTAINER-SHA256}
  printf '%s' "$content"
}

normalized_definition() {
  local file=$1
  local content

  content=$(<"$file")
  content=${content//nvim_container_x86/nvim_container_ARCH}
  content=${content//nvim_container_aarch64/nvim_container_ARCH}
  content=${content//x86_64/CONTAINER_ARCH}
  content=${content//aarch64/CONTAINER_ARCH}
  printf '%s' "$content"
}

normalized_architecture_script() {
  local file=$1
  local architecture=$2
  local content

  content=$(<"$file")
  case $architecture in
    x86)
      content=${content//linux\/x86_64/linux\/CONTAINER_ARCH}
      content=${content//\/x86\//\/CONTAINER_ARCH\/}
      content=${content//nvim_container_x86/nvim_container_ARCH}
      content=${content//configure_docker_build_storage x86_64/configure_docker_build_storage CONTAINER_ARCH}
      content=${content//buildx exec --architecture x86_64/buildx exec --architecture CONTAINER_ARCH}
      content=${content//x86_64/CONTAINER_ARCH}
      content=${content//nvim-x86/nvim-CONTAINER_ARCH}
      ;;
    aarch64)
      content=${content//linux\/arm64/linux\/CONTAINER_ARCH}
      content=${content//\/aarch64\//\/CONTAINER_ARCH\/}
      content=${content//nvim_container_aarch64/nvim_container_ARCH}
      content=${content//configure_docker_build_storage aarch64/configure_docker_build_storage CONTAINER_ARCH}
      content=${content//buildx exec --architecture aarch64/buildx exec --architecture CONTAINER_ARCH}
      content=${content//aarch64/CONTAINER_ARCH}
      content=${content//nvim-aarch64/nvim-CONTAINER_ARCH}
      ;;
    *)
      printf 'unsupported container architecture: %s\n' "$architecture" >&2
      exit 1
      ;;
  esac
  printf '%s' "$content"
}

assert_architecture_script_parity() {
  local description=$1
  local x86_script=$2
  local arm_script=$3
  local x86_normalized
  local arm_normalized

  x86_normalized=$(normalized_architecture_script "$x86_script" x86)
  arm_normalized=$(normalized_architecture_script "$arm_script" aarch64)
  if [[ $x86_normalized != "$arm_normalized" ]]; then
    printf 'x86 and aarch64 %s differ outside architecture identifiers\n' "$description" >&2
    diff -u <(printf '%s\n' "$x86_normalized") <(printf '%s\n' "$arm_normalized") >&2 || true
    exit 1
  fi
}

assert_no_ct_library_sources
assert_native_build_commands
assert_x86_package_staging

assert_orchestration_invocations() {
  local architecture=$1
  local platform cache_architecture build_context
  case $architecture in
    x86)
      platform=linux/x86_64
      cache_architecture=x86_64
      build_context=$repo/nvim
      ;;
    aarch64)
      platform=linux/arm64
      cache_architecture=aarch64
      build_context=$repo/nvim
      ;;
    ppc64le)
      platform=linux/ppc64le
      cache_architecture=ppc64le
      build_context=$repo/nvim/ppc64le
      ;;
    *)
      printf 'unsupported orchestration architecture: %s\n' "$architecture" >&2
      exit 1
      ;;
  esac
  local image="nvim_container_$architecture"
  local build_script="$repo/nvim/$architecture/${image}_build.sh"
  local dockerfile="$repo/nvim/$architecture/${image}.dockerfile"
  local export_tar="${image}.tar"
  local definition="${image}.def"
  local sif="${image}.sif"
  local fake_bin="$test_tmpdir/$architecture/bin"
  local command_log="$test_tmpdir/$architecture/commands"
  local home="$test_tmpdir/$architecture/home"
  local config="$home/.config/ct_runtime.conf"
  local storage="$test_tmpdir/$architecture/runtime storage"
  local singularity_cache="$storage/singularity cache"
  local singularity_tmp="$storage/singularity tmp"
  local docker_cache="$storage/docker cache"
  local docker_tmp="$storage/docker tmp"
  local architecture_cache="$docker_cache/$cache_architecture"
  local current_cache="$architecture_cache/current"
  local expected

  mkdir -p "$fake_bin" "$home/.config"
  printf '%s\n' \
    "CT_SINGULARITY_CACHE_DIR=$singularity_cache" \
    "CT_SINGULARITY_TMP_DIR=$singularity_tmp" \
    "CT_DOCKER_BUILD_CACHE_DIR=$docker_cache" \
    "CT_DOCKER_BUILD_TMP_DIR=$docker_tmp" > "$config"
  chmod 600 "$config"
  for command in docker singularity apptainer; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'command=${0##*/}' \
      'printf "%s" "$command" >> "$NVIM_CONTAINER_COMMAND_LOG"' \
      'case "$command:${1:-}" in' \
      '  docker:buildx) printf " <TMPDIR=%s>" "${TMPDIR:-}" >> "$NVIM_CONTAINER_COMMAND_LOG" ;;' \
      '  singularity:*|apptainer:*) printf " <CACHE=%s> <TMP=%s>" "${SINGULARITY_CACHEDIR:-${APPTAINER_CACHEDIR:-}}" "${SINGULARITY_TMPDIR:-${APPTAINER_TMPDIR:-}}" >> "$NVIM_CONTAINER_COMMAND_LOG" ;;' \
      'esac' \
      'for argument in "$@"; do' \
      '  display=$argument' \
      '  if [[ $argument == "type=local,dest=$NVIM_CONTAINER_CACHE_NAMESPACE"/.next.*,mode=max ]]; then' \
      '    cache_directory=${argument#type=local,dest=}' \
      '    cache_directory=${cache_directory%,mode=max}' \
      '    mkdir -p "$cache_directory"' \
      '    : > "$cache_directory/index.json"' \
      '    : > "$cache_directory/generation-$NVIM_CONTAINER_BUILD_ITERATION"' \
      '    display=type=local,dest=CACHE_STAGING,mode=max' \
      '  fi' \
      '  printf " <%s>" "$display" >> "$NVIM_CONTAINER_COMMAND_LOG"' \
      'done' \
      'printf "\n" >> "$NVIM_CONTAINER_COMMAND_LOG"' > "$fake_bin/$command"
    chmod +x "$fake_bin/$command"
  done

  local iteration
  for iteration in 1 2; do
    (
      cd "$repo/nvim/$architecture"
      HOME=$home CT_RUNTIME_CFG=$config TMPDIR='' \
        CT_ROOT=$container_tools_test_root \
        NVIM_CONTAINER_BUILD_ITERATION=$iteration \
        NVIM_CONTAINER_CACHE_NAMESPACE=$architecture_cache \
        NVIM_CONTAINER_COMMAND_LOG=$command_log PATH="$fake_bin:$PATH" \
        bash "$build_script"
    )
  done

  expected=$(printf '%s\n' \
    "docker <TMPDIR=$docker_tmp> <buildx> <build> <--cache-to> <type=local,dest=CACHE_STAGING,mode=max> <--platform> <$platform> <-f> <$dockerfile> <-t> <$image:latest> <--load> <$build_context>" \
    "docker <save> <$image:latest> <-o> <$export_tar>" \
    "singularity <CACHE=$singularity_cache> <TMP=$singularity_tmp> <build> <--force> <--fakeroot> <$sif> <$definition>" \
    "docker <TMPDIR=$docker_tmp> <buildx> <build> <--cache-from> <type=local,src=$current_cache> <--cache-to> <type=local,dest=CACHE_STAGING,mode=max> <--platform> <$platform> <-f> <$dockerfile> <-t> <$image:latest> <--load> <$build_context>" \
    "docker <save> <$image:latest> <-o> <$export_tar>" \
    "singularity <CACHE=$singularity_cache> <TMP=$singularity_tmp> <build> <--force> <--fakeroot> <$sif> <$definition>")
  if ! diff -u <(printf '%s\n' "$expected") "$command_log"; then
    printf 'unexpected %s orchestration command sequence\n' "$architecture" >&2
    exit 1
  fi

  for directory in "$singularity_cache" "$singularity_tmp" "$docker_cache" "$docker_tmp" "$architecture_cache" "$current_cache"; do
    if [[ ! -d $directory || $(stat -Lc '%a' -- "$directory") != 700 ]]; then
      printf 'runtime storage directory is not private: %s\n' "$directory" >&2
      exit 1
    fi
  done
  [[ -f $current_cache/generation-2 && ! -e $current_cache/generation-1 ]]
  shopt -s nullglob
  local stale_generations=("$architecture_cache"/.next.*)
  shopt -u nullglob
  if (( ${#stale_generations[@]} != 0 )) || [[ -e $architecture_cache/.previous || -L $architecture_cache/.previous ]]; then
    printf 'stale Docker cache generations remain for %s\n' "$architecture" >&2
    exit 1
  fi
}

assert_alternate_runtime_selection() {
  local fake_bin="$test_tmpdir/alternate-runtime/bin"
  local home="$test_tmpdir/alternate-runtime/home"
  local config="$home/.config/ct_runtime.conf"
  local command_log="$test_tmpdir/alternate-runtime/commands"
  local cache="$test_tmpdir/alternate-runtime/cache"
  local tmp="$test_tmpdir/alternate-runtime/tmp"
  local utility
  mkdir -p "$fake_bin" "$home/.config"
  for utility in bash cat chmod dirname install realpath stat timeout; do
    ln -s "$(command -v "$utility")" "$fake_bin/$utility"
  done
  printf '%s\n' \
    "CT_SINGULARITY_CACHE_DIR=$cache" \
    "CT_SINGULARITY_TMP_DIR=$tmp" > "$config"
  chmod 600 "$config"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "apptainer <%s> <%s>" "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" > "$NVIM_CONTAINER_COMMAND_LOG"' \
    'printf " <%s>" "$@" >> "$NVIM_CONTAINER_COMMAND_LOG"' \
    'printf "\n" >> "$NVIM_CONTAINER_COMMAND_LOG"' > "$fake_bin/apptainer"
  chmod +x "$fake_bin/apptainer"

  (
    cd "$repo/nvim/x86"
    HOME=$home CT_RUNTIME_CFG=$config NVIM_CONTAINER_COMMAND_LOG=$command_log \
      CT_ROOT=$container_tools_test_root \
      PATH=$fake_bin /bin/bash ./nvim_container_x86_build_singularity.sh
  )
  expected="apptainer <$cache> <$tmp> <build> <--force> <--fakeroot> <nvim_container_x86.sif> <nvim_container_x86.def>"
  [[ $(<"$command_log") == "$expected" ]] || {
    printf '%s\n' 'Apptainer fallback did not receive configured runtime storage' >&2
    exit 1
  }

  rm "$fake_bin/apptainer"
  if missing_output=$(
    cd "$repo/nvim/x86"
    HOME=$home CT_RUNTIME_CFG=$config CT_ROOT=$container_tools_test_root PATH=$fake_bin \
      /bin/bash ./nvim_container_x86_build_singularity.sh 2>&1
  ); then
    printf '%s\n' 'Singularity build accepted a host with no supported runtime' >&2
    exit 1
  fi
  [[ $missing_output == *'Neither Singularity nor Apptainer are installed'* ]] || {
    printf '%s\n' 'missing-runtime failure did not explain the prerequisite' >&2
    exit 1
  }
}

assert_failed_build_discards_cache() {
  local fake_bin="$test_tmpdir/failed-build/bin"
  local home="$test_tmpdir/failed-build/home"
  local config="$home/.config/ct_runtime.conf"
  local cache="$test_tmpdir/failed-build/cache"
  local namespace="$cache/x86_64"
  mkdir -p "$fake_bin" "$home/.config"
  printf 'CT_DOCKER_BUILD_CACHE_DIR=%s\n' "$cache" > "$config"
  chmod 600 "$config"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'for argument in "$@"; do' \
    '  if [[ $argument == type=local,dest=*,mode=max ]]; then' \
    '    cache_directory=${argument#type=local,dest=}' \
    '    cache_directory=${cache_directory%,mode=max}' \
    '    mkdir -p "$cache_directory"' \
    '    : > "$cache_directory/partial"' \
    '  fi' \
    'done' \
    'exit 42' > "$fake_bin/docker"
  chmod +x "$fake_bin/docker"

  if HOME=$home CT_RUNTIME_CFG=$config CT_ROOT=$container_tools_test_root TMPDIR=/tmp PATH="$fake_bin:$PATH" \
    bash "$repo/nvim/x86/nvim_container_x86_build_docker.sh"; then
    printf '%s\n' 'failed Docker build returned success' >&2
    exit 1
  else
    local status=$?
  fi
  [[ $status == 42 && ! -e $namespace/current && ! -L $namespace/current ]] || {
    printf '%s\n' 'failed Docker build retained or promoted an incomplete cache' >&2
    exit 1
  }
  shopt -s nullglob
  local incomplete=("$namespace"/.next.*)
  shopt -u nullglob
  (( ${#incomplete[@]} == 0 )) || {
    printf '%s\n' 'failed Docker build left a staging cache behind' >&2
    exit 1
  }
  (
    exec 8> "$namespace/.lock"
    flock -n 8
  ) || {
    printf '%s\n' 'failed Docker build did not release its cache lock' >&2
    exit 1
  }
}

assert_child_signal_propagates() {
  local fake_bin="$test_tmpdir/signaled-build/bin"
  local home="$test_tmpdir/signaled-build/home"
  local config="$home/.config/ct_runtime.conf"
  local docker_cache="$test_tmpdir/signaled-build/docker-cache"
  local docker_namespace="$docker_cache/x86_64"
  local singularity_cache="$test_tmpdir/signaled-build/singularity-cache"
  local singularity_tmp="$test_tmpdir/signaled-build/singularity-tmp"
  local status

  mkdir -p "$fake_bin" "$home/.config"
  printf '%s\n' \
    "CT_SINGULARITY_CACHE_DIR=$singularity_cache" \
    "CT_SINGULARITY_TMP_DIR=$singularity_tmp" \
    "CT_DOCKER_BUILD_CACHE_DIR=$docker_cache" > "$config"
  chmod 600 "$config"
  printf '%s\n' '#!/usr/bin/env bash' 'kill -TERM "$$"' > "$fake_bin/docker"
  printf '%s\n' '#!/usr/bin/env bash' 'kill -TERM "$$"' > "$fake_bin/apptainer"
  chmod +x "$fake_bin/docker" "$fake_bin/apptainer"

  set +e
  HOME=$home CT_RUNTIME_CFG=$config CT_ROOT=$container_tools_test_root PATH="$fake_bin:$PATH" \
    bash "$repo/nvim/x86/nvim_container_x86_build_docker.sh"
  status=$?
  set -e
  [[ $status == 143 ]] || {
    printf 'Docker Buildx child signal returned %s instead of 143\n' "$status" >&2
    exit 1
  }
  [[ ! -e $docker_namespace/current && ! -L $docker_namespace/current ]] || {
    printf '%s\n' 'signaled Docker Buildx child promoted a cache generation' >&2
    exit 1
  }
  shopt -s nullglob
  local staging=("$docker_namespace"/.next.*)
  shopt -u nullglob
  (( ${#staging[@]} == 0 )) || {
    printf '%s\n' 'signaled Docker Buildx child left a staging generation' >&2
    exit 1
  }

  set +e
  (
    cd "$repo/nvim/x86"
    HOME=$home CT_RUNTIME_CFG=$config CT_ROOT=$container_tools_test_root PATH="$fake_bin:$PATH" \
      bash ./nvim_container_x86_build_singularity.sh
  )
  status=$?
  set -e
  [[ $status == 143 ]] || {
    printf 'Apptainer child signal returned %s instead of 143\n' "$status" >&2
    exit 1
  }
}

for arch in x86 aarch64 ppc64le; do
  dockerfile="$repo/nvim/$arch/nvim_container_${arch}.dockerfile"
  definition="$repo/nvim/$arch/nvim_container_${arch}.def"
  assert_active "$dockerfile" 'ffmpeg-free'
  assert_active "$dockerfile" 'ShellCheck'
  assert_active "$dockerfile" 'ARG AST_GREP_VERSION=0.44.1'
  assert_active "$dockerfile" 'cargo install --locked --root /opt/msk/ast-grep --version "${AST_GREP_VERSION}"'
  assert_active "$dockerfile" 'ln -s /opt/msk/ast-grep/bin/ast-grep /usr/bin/ast-grep'
  assert_not_contains "$dockerfile" '--root /usr --version "${AST_GREP_VERSION}"'
  assert_active "$dockerfile" '"jsonschema>=4.23,<5"'
  assert_active "$dockerfile" "python3 -c 'from jsonschema import Draft202012Validator'"
  assert_active "$dockerfile" 'ast-grep --version'
  assert_active "$dockerfile" 'ffmpeg -version'
  assert_active "$dockerfile" 'shellcheck --version'
  assert_active "$definition" 'export MSK_NPM_GLOBAL_ROOT="${MSK_NPM_GLOBAL_BASE}"'
  assert_not_contains "$definition" 'MSK_CONTAINER_ARCH'
  assert_not_contains "$definition" 'MSK_NODE_GLOBAL_KEY'
  assert_not_contains "$definition" 'NPM_CONFIG_PREFIX'
  assert_not_contains "$definition" 'MSK_NPM_GLOBAL_ROOT/bin'
done

x86="$repo/nvim/x86/nvim_container_x86.dockerfile"
arm="$repo/nvim/aarch64/nvim_container_aarch64.dockerfile"
manifest="$repo/nvim/component-manifest.json"
x86_opencode_sha256=4cdd0b8c77106c4efdca5278f86ffe5e9af8602aedcfca413600bb3abe778b1a
arm_opencode_sha256=211562aa07f70baf178fa2e7726839178a256eef26db1b6651d3ba836b021433
bun_version=1.3.14
x86_bun_sha256=951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f
arm_bun_sha256=a27ffb63a8310375836e0d6f668ae17fa8d8d18b88c37c821c65331973a19a3b
x86_definition="$repo/nvim/x86/nvim_container_x86.def"
arm_definition="$repo/nvim/aarch64/nvim_container_aarch64.def"
x86_docker_build="$repo/nvim/x86/nvim_container_x86_build_docker.sh"
arm_docker_build="$repo/nvim/aarch64/nvim_container_aarch64_build_docker.sh"
x86_docker_export="$repo/nvim/x86/nvim_container_x86_export_docker.sh"
arm_docker_export="$repo/nvim/aarch64/nvim_container_aarch64_export_docker.sh"
x86_build="$repo/nvim/x86/nvim_container_x86_build.sh"
arm_build="$repo/nvim/aarch64/nvim_container_aarch64_build.sh"
x86_singularity_build="$repo/nvim/x86/nvim_container_x86_build_singularity.sh"
arm_singularity_build="$repo/nvim/aarch64/nvim_container_aarch64_build_singularity.sh"
runtime_test="$repo/tests/container_tools_selected_root_runtime_test.sh"

python3 - "$manifest" "$x86" "$arm" <<'PY'
import json
import re
import sys

manifest_path, *dockerfile_paths = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
assert manifest["schema"] == 1
assert manifest["component_id"] == "nvim-image"
assert manifest["build_id"] == "nvim-0.12.4-node-24.18.0-opencode-1.18.9-mkchad.3"
ships = manifest["relationships"]
assert 1 <= len(ships) <= 8
assert all(item["type"] == "ships" and item["contract"]["suffix_policy"] == "literal" for item in ships)
assert len({item["id"] for item in ships}) == len(ships)
versions = {item["target_component"]: item["contract"]["version"] for item in ships}
assert versions == {
    "prereq-neovim": "0.12.4",
    "prereq-node": "24.18.0",
    "opencode": "1.18.9-mkchad.3",
}
for path in dockerfile_paths:
    text = open(path, encoding="utf-8").read()
    manifest_copy = "COPY component-manifest.json /usr/share/mkchad/component-manifest.json"
    assert text.count(manifest_copy) == 1
    active_lines = [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert active_lines[-1] == manifest_copy
    assert re.search(r"ARG OPENCODE_VERSION=" + re.escape(versions["opencode"]) + r"(?:\n|\r\n)", text)
    assert re.search(r"ENV NODE_VER=" + re.escape(versions["prereq-node"]) + r"(?:\n|\r\n)", text)
    assert "--branch v" + versions["prereq-neovim"] in text
PY
assert_active "$x86_docker_build" '--platform linux/x86_64'
assert_active "$x86_docker_build" '-f "$context/x86/nvim_container_x86.dockerfile"'
assert_active "$x86_docker_build" '-t nvim_container_x86:latest'
assert_active "$x86_docker_build" '--load "$context"'
assert_active "$arm_docker_build" '--platform linux/arm64'
assert_active "$arm_docker_build" '-f "$context/aarch64/nvim_container_aarch64.dockerfile"'
assert_active "$arm_docker_build" '-t nvim_container_aarch64:latest'
assert_active "$arm_docker_build" '--load "$context"'

x86_luals_build=$(printf '%s\n' \
  "RUN git clone --depth 1 --branch 3.17.1 https://github.com/LuaLS/lua-language-server /nvim/lua-language-server && \\" \
  "    cd /nvim/lua-language-server && \\" \
  '    bash ./make.sh')
arm_luals_build=$(printf '%s\n' \
  '# Adjusted build process because tests fail on aarch64 on x64 host.' \
  '# Build process copied from `make.sh` and modified to avoid tests' \
  "RUN git clone --depth 1 --branch 3.17.1 https://github.com/LuaLS/lua-language-server /nvim/lua-language-server && \\" \
  "    cd /nvim/lua-language-server && \\" \
  "    git submodule update --init --recursive && \\" \
  "    pushd 3rd/luamake && \\" \
  "    ./compile/build.sh && \\" \
  "    popd && \\" \
  '    3rd/luamake/luamake all')
assert_contains_once "$x86" "$x86_luals_build" 'x86 LuaLS build'
assert_contains_once "$arm" "$arm_luals_build" 'aarch64 LuaLS build'

assert_active "$x86" 'node-v${NODE_VER}-linux-x64.tar.gz'
assert_active "$x86" 'ENV PATH="/nvim/node-v${NODE_VER}-linux-x64/bin:$PATH"'
assert_not_contains "$x86" 'node-v${NODE_VER}-linux-arm64'
assert_active "$x86" 'ARG OPENCODE_ASSET=opencode-ai-1.18.9-mkchad.3-linux-x64.tgz'
assert_active "$x86" "ARG OPENCODE_SHA256=$x86_opencode_sha256"
assert_contains_once "$x86" 'ARG OPENCODE_VERSION=1.18.9-mkchad.3' 'OpenCode version pin'
assert_contains_once "$x86" 'ARG OPENCODE_RELEASE_BASE=https://github.com/krafczyk/opencode/releases/download/v1.18.9-mkchad.3' 'OpenCode release base pin'
assert_contains_once "$x86" 'ARG OPENCODE_ASSET=opencode-ai-1.18.9-mkchad.3-linux-x64.tgz' 'OpenCode x64 asset pin'
assert_contains_once "$x86" "ARG OPENCODE_SHA256=$x86_opencode_sha256" 'OpenCode x64 checksum pin'
assert_active "$arm" 'node-v${NODE_VER}-linux-arm64.tar.gz'
assert_active "$arm" 'ENV PATH="/nvim/node-v${NODE_VER}-linux-arm64/bin:$PATH"'
assert_not_contains "$arm" 'node-v${NODE_VER}-linux-x64'
assert_active "$arm" 'ARG OPENCODE_ASSET=opencode-ai-1.18.9-mkchad.3-linux-arm64.tgz'
assert_active "$arm" "ARG OPENCODE_SHA256=$arm_opencode_sha256"
assert_contains_once "$arm" 'ARG OPENCODE_VERSION=1.18.9-mkchad.3' 'OpenCode version pin'
assert_contains_once "$arm" 'ARG OPENCODE_RELEASE_BASE=https://github.com/krafczyk/opencode/releases/download/v1.18.9-mkchad.3' 'OpenCode release base pin'
assert_contains_once "$arm" 'ARG OPENCODE_ASSET=opencode-ai-1.18.9-mkchad.3-linux-arm64.tgz' 'OpenCode ARM64 asset pin'
assert_contains_once "$arm" "ARG OPENCODE_SHA256=$arm_opencode_sha256" 'OpenCode ARM64 checksum pin'
assert_active "$x86" "ARG BUN_VERSION=$bun_version"
assert_active "$x86" 'ARG BUN_RELEASE_BASE=https://github.com/oven-sh/bun/releases/download/bun-v1.3.14'
assert_active "$x86" 'ARG BUN_ASSET=bun-linux-x64.zip'
assert_active "$x86" "ARG BUN_SHA256=$x86_bun_sha256"
assert_contains_once "$x86" "ARG BUN_VERSION=$bun_version" 'Bun version pin'
assert_contains_once "$x86" 'ARG BUN_RELEASE_BASE=https://github.com/oven-sh/bun/releases/download/bun-v1.3.14' 'Bun release base pin'
assert_contains_once "$x86" 'ARG BUN_ASSET=bun-linux-x64.zip' 'Bun x64 asset pin'
assert_contains_once "$x86" "ARG BUN_SHA256=$x86_bun_sha256" 'Bun x64 checksum pin'
assert_active "$arm" "ARG BUN_VERSION=$bun_version"
assert_active "$arm" 'ARG BUN_RELEASE_BASE=https://github.com/oven-sh/bun/releases/download/bun-v1.3.14'
assert_active "$arm" 'ARG BUN_ASSET=bun-linux-aarch64.zip'
assert_active "$arm" "ARG BUN_SHA256=$arm_bun_sha256"
assert_contains_once "$arm" "ARG BUN_VERSION=$bun_version" 'Bun version pin'
assert_contains_once "$arm" 'ARG BUN_RELEASE_BASE=https://github.com/oven-sh/bun/releases/download/bun-v1.3.14' 'Bun release base pin'
assert_contains_once "$arm" 'ARG BUN_ASSET=bun-linux-aarch64.zip' 'Bun ARM64 asset pin'
assert_contains_once "$arm" "ARG BUN_SHA256=$arm_bun_sha256" 'Bun ARM64 checksum pin'
assert_active "$x86_definition" 'From: nvim_container_x86.tar'
assert_not_contains "$x86_definition" 'nvim_container_aarch64'
assert_active "$arm_definition" 'From: nvim_container_aarch64.tar'
assert_not_contains "$arm_definition" 'nvim_container_x86'

x86_normalized=$(normalized_dockerfile "$x86" "$x86_luals_build")
arm_normalized=$(normalized_dockerfile "$arm" "$arm_luals_build")
if [[ $x86_normalized != "$arm_normalized" ]]; then
  printf '%s\n' 'x86 and aarch64 Dockerfiles differ outside architecture allowances' >&2
  diff -u <(printf '%s\n' "$x86_normalized") <(printf '%s\n' "$arm_normalized") >&2 || true
  exit 1
fi

x86_definition_normalized=$(normalized_definition "$x86_definition")
arm_definition_normalized=$(normalized_definition "$arm_definition")
if [[ $x86_definition_normalized != "$arm_definition_normalized" ]]; then
  printf '%s\n' 'x86 and aarch64 Apptainer definitions differ' >&2
  diff -u \
    <(printf '%s\n' "$x86_definition_normalized") \
    <(printf '%s\n' "$arm_definition_normalized") >&2 || true
  exit 1
fi

assert_architecture_script_parity 'Docker build scripts' "$x86_docker_build" "$arm_docker_build"
assert_architecture_script_parity 'Docker export scripts' "$x86_docker_export" "$arm_docker_export"
assert_architecture_script_parity 'top-level build scripts' "$x86_build" "$arm_build"
assert_architecture_script_parity 'Singularity/Apptainer build scripts' "$x86_singularity_build" "$arm_singularity_build"
if [[ ${CONTAINER_TOOLS_TOOLING_RUN_RUNTIME:-0} == 1 ]]; then
  assert_orchestration_invocations x86
  assert_alternate_runtime_selection
  assert_failed_build_discards_cache
  assert_child_signal_propagates
fi

assert_same_arguments 'dnf install -y ' 'direct DNF package'
assert_same_arguments 'pip3 install --prefix /usr ' 'direct pip package'
assert_same_arguments 'npm install -g basedpyright ' 'global npm package'
assert_same_arguments 'npm install --prefix /opt/msk/browser-tools --save-exact ' 'browser npm package'

for dockerfile in "$x86" "$arm"; do
  assert_active "$dockerfile" 'FROM docker.io/library/fedora:43@sha256:762d73ba1c455232b0272c5d445a34f36c4b9f421cbc05ce8102552325b6a222'
  assert_not_contains "$dockerfile" 'quay.io/fedora/fedora'
  assert_active "$dockerfile" 'ENV NODE_VER=24.18.0'
  assert_active "$dockerfile" 'ARG STYLUA_VERSION=2.5.2'
  assert_active "$dockerfile" 'ARG LUACHECK_VERSION=1.2.0-1'
  assert_active "$dockerfile" 'selenium==4.46.0'
  assert_active "$dockerfile" 'py-spy'
  assert_active "$dockerfile" 'openssl-devel memray age'
  assert_active "$dockerfile" 'ShellCheck shfmt uv'
  assert_active "$dockerfile" 'age --version'
  assert_active "$dockerfile" 'age-keygen --version'
  assert_active "$dockerfile" 'shfmt --version'
  assert_active "$dockerfile" 'uv --version'
  assert_active "$dockerfile" 'ENV JDTLS_MILESTONE=1.56.0'
  assert_active "$dockerfile" 'test -x /nvim/jdtls/bin/jdtls'
  assert_active "$dockerfile" 'COPY container-tools-package.tar.gz /tmp/container-tools-package.tar.gz'
  assert_active "$dockerfile" 'tar -xzf /tmp/container-tools-package.tar.gz --strip-components=1 -C /opt/msk/container-tools'
  assert_active "$dockerfile" 'org.mkchad.container-tools.sha256='
  assert_active "$dockerfile" 'git clone --depth 1 --branch v2.1-agentzh https://github.com/openresty/luajit2'
  assert_active "$dockerfile" 'git clone --depth 1 --branch v0.12.4 https://github.com/neovim/neovim'
  assert_active "$dockerfile" '-DUSE_BUNDLED=ON'
  assert_active "$dockerfile" '-DUSE_BUNDLED_LUAJIT=OFF'
  assert_active "$dockerfile" 'git clone --depth 1 --branch 3.17.1 https://github.com/LuaLS/lua-language-server'
  assert_active "$dockerfile" 'npm install -g neovim'
  assert_active "$dockerfile" 'ARG OPENCODE_VERSION=1.18.9-mkchad.3'
  assert_active "$dockerfile" 'ARG OPENCODE_RELEASE_BASE=https://github.com/krafczyk/opencode/releases/download/v1.18.9-mkchad.3'
  assert_active "$dockerfile" "curl --fail --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --retry-max-time 1800 --proto '=https' --tlsv1.2 --output \"\${opencode_tarball}\""
  assert_active "$dockerfile" '"${OPENCODE_RELEASE_BASE}/${OPENCODE_ASSET}"'
  assert_active "$dockerfile" 'echo "${OPENCODE_SHA256}  ${opencode_tarball}" | sha256sum --check --strict -'
  assert_active "$dockerfile" 'npm install -g "${opencode_tarball}"'
  assert_contains_once "$dockerfile" 'echo "${OPENCODE_SHA256}  ${opencode_tarball}" | sha256sum --check --strict -' 'OpenCode checksum verification'
  assert_contains_once "$dockerfile" 'npm install -g "${opencode_tarball}"' 'OpenCode package installation'
  assert_active_before "$dockerfile" 'echo "${OPENCODE_SHA256}  ${opencode_tarball}" | sha256sum --check --strict -' 'npm install -g "${opencode_tarball}"'
  assert_active "$dockerfile" 'test "$(opencode --version)" = "${OPENCODE_VERSION}"'
  assert_active "$dockerfile" 'curl --fail --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --retry-max-time 1800 --proto '\''=https'\'' --tlsv1.2 --output "${bun_archive}"'
  assert_active "$dockerfile" '"${BUN_RELEASE_BASE}/${BUN_ASSET}"'
  assert_active "$dockerfile" 'echo "${BUN_SHA256}  ${bun_archive}" | sha256sum --check --strict -'
  assert_active "$dockerfile" 'unzip -q "${bun_archive}" -d "${bun_extract}"'
  assert_active "$dockerfile" 'install -D -m 0755 "${bun_extract}/${BUN_ASSET%.zip}/bun" /opt/msk/bun/bin/bun'
  assert_active "$dockerfile" 'ln -s /opt/msk/bun/bin/bun /usr/bin/bun'
  assert_active "$dockerfile" 'ln -s /opt/msk/bun/bin/bun /usr/bin/bunx'
  assert_active "$dockerfile" 'rm -rf "${bun_archive}" "${bun_extract}"'
  assert_active "$dockerfile" 'test "$(bun --version)" = "${BUN_VERSION}"'
  assert_active "$dockerfile" 'test "$(bunx --version)" = "${BUN_VERSION}"'
  assert_contains_once "$dockerfile" 'curl --fail --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --retry-max-time 1800 --proto '\''=https'\'' --tlsv1.2 --output "${bun_archive}"' 'Bun download'
  assert_contains_once "$dockerfile" 'echo "${BUN_SHA256}  ${bun_archive}" | sha256sum --check --strict -' 'Bun checksum verification'
  assert_contains_once "$dockerfile" 'unzip -q "${bun_archive}" -d "${bun_extract}"' 'Bun extraction'
  assert_contains_once "$dockerfile" 'install -D -m 0755 "${bun_extract}/${BUN_ASSET%.zip}/bun" /opt/msk/bun/bin/bun' 'Bun installation'
  assert_contains_once "$dockerfile" 'ln -s /opt/msk/bun/bin/bun /usr/bin/bun;' 'Bun command link'
  assert_contains_once "$dockerfile" 'ln -s /opt/msk/bun/bin/bun /usr/bin/bunx;' 'Bunx command link'
  assert_contains_once "$dockerfile" 'test "$(bun --version)" = "${BUN_VERSION}"' 'Bun version check'
  assert_contains_once "$dockerfile" 'test "$(bunx --version)" = "${BUN_VERSION}"' 'Bunx version check'
  assert_active_before "$dockerfile" 'echo "${BUN_SHA256}  ${bun_archive}" | sha256sum --check --strict -' 'install -D -m 0755 "${bun_extract}/${BUN_ASSET%.zip}/bun" /opt/msk/bun/bin/bun'
  assert_active_before "$dockerfile" 'echo "${BUN_SHA256}  ${bun_archive}" | sha256sum --check --strict -' 'unzip -q "${bun_archive}" -d "${bun_extract}"'
  assert_active_before "$dockerfile" 'install -D -m 0755 "${bun_extract}/${BUN_ASSET%.zip}/bun" /opt/msk/bun/bin/bun' 'test "$(bun --version)" = "${BUN_VERSION}"'
  assert_not_contains "$dockerfile" '"bun@${BUN_VERSION}"'
  assert_not_contains "$dockerfile" 'bun install --frozen-lockfile'
  assert_not_contains "$dockerfile" 'https://github.com/krafczyk/opencode.git'
  assert_not_contains "$dockerfile" 'OPENCODE_REVISION'
  assert_not_contains "$dockerfile" 'bun run build --single --skip-install'
  assert_not_contains "$dockerfile" 'opencode-ai@'
  assert_active "$dockerfile" 'ARG AGENT_BROWSER_VERSION=0.32.2'
  assert_active "$dockerfile" 'ARG PLAYWRIGHT_VERSION=1.61.1'
  assert_active "$dockerfile" 'ARG PUPPETEER_VERSION=25.3.0'
  assert_active "$dockerfile" 'ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium-browser'
  assert_active "$dockerfile" '"agent-browser@${AGENT_BROWSER_VERSION}"'
  assert_active "$dockerfile" 'playwright install chromium'
  assert_active "$dockerfile" 'opencode --version'
  assert_active "$dockerfile" 'agent-browser --version'
  assert_not_contains "$dockerfile" 'agent-browser install'
  for package in \
    bubblewrap libtalloc-devel pkgconf-pkg-config musl-gcc musl-devel musl-libc-static; do
    assert_dnf_package "$dockerfile" "$package"
  done
  assert_active_once "$dockerfile" 'ARG PROOT_VERSION=v5.4.0' 'PRoot version pin'
  assert_active_once "$dockerfile" 'ARG PROOT_REVISION=bd5a5f63d72f8210d8cee76195eb9f0749e5bd70' 'PRoot revision pin'
  assert_active_once "$dockerfile" 'ARG PROOT_UTHASH_REVISION=e493aa90a2833b4655927598f169c31cfcdf7861' 'PRoot uthash revision pin'
  assert_active_once "$dockerfile" 'git clone --depth 1 --single-branch --branch "${PROOT_VERSION}"' 'PRoot release checkout'
  assert_active_once "$dockerfile" 'git -C /tmp/proot checkout --detach "${PROOT_REVISION}"' 'PRoot detached checkout'
  assert_active_once "$dockerfile" 'test "$(git -C /tmp/proot rev-parse HEAD)" = "${PROOT_REVISION}"' 'PRoot root revision verification'
  assert_active_once "$dockerfile" 'test "$(git -C /tmp/proot ls-tree --object-only HEAD lib/uthash)" = "${PROOT_UTHASH_REVISION}"' 'PRoot uthash gitlink verification'
  assert_active_once "$dockerfile" 'git -C /tmp/proot submodule update --init lib/uthash' 'PRoot uthash initialization'
  assert_not_contains "$dockerfile" 'git -C /tmp/proot submodule update --init --recursive'
  assert_active_once "$dockerfile" 'test "$(git -C /tmp/proot/lib/uthash rev-parse HEAD)" = "${PROOT_UTHASH_REVISION}"' 'PRoot uthash revision verification'
  assert_active_once "$dockerfile" 'make -C /tmp/proot/src proot' 'PRoot build'
  assert_only_proot_make_target "$dockerfile"
  assert_not_contains "$dockerfile" 'make -C /tmp/proot/src care'
  assert_not_contains "$dockerfile" 'make -C /tmp/proot/src qemu'
  assert_not_contains_case_insensitive "$dockerfile" 'care'
  assert_not_contains_case_insensitive "$dockerfile" 'qemu'
  assert_active_once "$dockerfile" 'install -D -m 0755 /tmp/proot/src/proot /opt/msk/proot/bin/proot' 'PRoot installation'
  assert_active_before "$dockerfile" 'git clone --depth 1 --single-branch --branch "${PROOT_VERSION}"' 'git -C /tmp/proot checkout --detach "${PROOT_REVISION}"'
  assert_active_before "$dockerfile" 'git -C /tmp/proot checkout --detach "${PROOT_REVISION}"' 'test "$(git -C /tmp/proot rev-parse HEAD)" = "${PROOT_REVISION}"'
  assert_active_before "$dockerfile" 'test "$(git -C /tmp/proot rev-parse HEAD)" = "${PROOT_REVISION}"' 'test "$(git -C /tmp/proot ls-tree --object-only HEAD lib/uthash)" = "${PROOT_UTHASH_REVISION}"'
  assert_active_before "$dockerfile" 'test "$(git -C /tmp/proot ls-tree --object-only HEAD lib/uthash)" = "${PROOT_UTHASH_REVISION}"' 'git -C /tmp/proot submodule update --init lib/uthash'
  assert_active_before "$dockerfile" 'git -C /tmp/proot submodule update --init lib/uthash' 'test "$(git -C /tmp/proot/lib/uthash rev-parse HEAD)" = "${PROOT_UTHASH_REVISION}"'
  assert_active_before "$dockerfile" 'test "$(git -C /tmp/proot/lib/uthash rev-parse HEAD)" = "${PROOT_UTHASH_REVISION}"' 'make -C /tmp/proot/src proot'
  assert_active_before "$dockerfile" 'make -C /tmp/proot/src proot' 'install -D -m 0755 /tmp/proot/src/proot /opt/msk/proot/bin/proot'
  assert_active "$dockerfile" 'install -D -m 0644 /tmp/proot/COPYING /opt/msk/proot/licenses/proot/COPYING'
  assert_active "$dockerfile" 'install -D -m 0644 /tmp/proot/lib/uthash/LICENSE /opt/msk/proot/licenses/uthash/LICENSE'
  assert_active "$dockerfile" 'ln -s /opt/msk/proot/bin/proot /usr/bin/proot'
  assert_active "$dockerfile" 'rm -rf /tmp/proot'
  assert_active "$dockerfile" 'bwrap --version'
  assert_active "$dockerfile" 'test -x /opt/msk/proot/bin/proot'
  assert_active "$dockerfile" 'test -L /usr/bin/proot'
  assert_active "$dockerfile" 'test "$(readlink /usr/bin/proot)" = /opt/msk/proot/bin/proot'
  assert_active "$dockerfile" 'test -f /opt/msk/proot/licenses/proot/COPYING'
  assert_active "$dockerfile" 'test -f /opt/msk/proot/licenses/uthash/LICENSE'
  assert_active "$dockerfile" 'proot --version | grep -Eq " ${PROOT_VERSION}(-[0-9a-f]{8})?$"'
  assert_active "$dockerfile" 'musl-gcc -std=c11 -static'
  assert_active "$dockerfile" "! grep -Fq ' INTERP '"
  assert_active "$dockerfile" '"${smoke_dir}/hello"'
  assert_active "$dockerfile" 'rm -rf "${smoke_dir}"'
done

# Removing a package from both image variants must fail even though its smoke
# command still mentions the package name.
for architecture in x86 aarch64; do
  source_dockerfile=$repo/nvim/$architecture/nvim_container_${architecture}.dockerfile
  fixture_dockerfile=$test_tmpdir/nvim_container_${architecture}.dockerfile
  fixture_content=$(<"$source_dockerfile")
  fixture_content=${fixture_content/'musl-gcc '/}
  printf '%s' "$fixture_content" > "$fixture_dockerfile"
  assert_active "$fixture_dockerfile" 'musl-gcc -std=c11 -static'
  if dnf_has_package "$fixture_dockerfile" musl-gcc; then
    printf 'DNF package guard accepted removed musl-gcc in %s\n' "$fixture_dockerfile" >&2
    exit 1
  fi
done

assert_active "$arm" 'git submodule update --init --recursive'
assert_active "$arm" './compile/build.sh'
assert_active "$arm" '3rd/luamake/luamake all'
assert_active "$x86" 'bash ./make.sh'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'agent-browser'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'opencode-ai'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_VERSION'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_REVISION'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_RELEASE_BASE'
assert_not_contains_case_insensitive "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'opencode'
for excluded in bubblewrap proot uthash musl-gcc musl-devel musl-libc-static; do
  assert_not_contains_case_insensitive "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" "$excluded"
done

assert_contains "$adr" '| `ffmpeg-free` | All |'
assert_contains "$adr" '| `ShellCheck` | All |'
assert_contains "$adr" '`docker.io/library/fedora:43@sha256:762d73ba1c455232b0272c5d445a34f36c4b9f421cbc05ce8102552325b6a222`'
assert_contains "$adr" 'Docker Official Image'
assert_contains "$adr" 'retention assumption'
assert_contains "$adr" 'not a contractual retention guarantee'
assert_contains "$adr" '`tests/fedora_base_availability_test.py`'
assert_contains "$adr" '`tests/fedora_base_availability_unit_test.py`'
assert_contains "$adr" 'checks every referenced config and'
assert_contains "$adr" 'layer blob without following registry redirects'
assert_contains "$adr" '| `shfmt` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `uv` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" 'not immutable'
assert_contains "$adr" 'exact-version runtime pins'
assert_contains "$adr" '| `age` | x86, ARM |'
assert_contains "$adr" '| `jsonschema` | All | `>=4.23,<5` |'
assert_contains "$adr" '| ast-grep | All | Cargo crate pinned to `0.44.1` with `--locked` |'
assert_contains "$adr" '| `agent-browser` | x86, ARM | Pinned to `0.32.2` |'
assert_contains "$adr" '| x86_64 | `24.18.0` | `linux-x64` |'
assert_contains "$adr" '| aarch64 | `24.18.0` | `linux-arm64` |'
assert_contains "$adr" '`linux-x64-node24`'
assert_contains "$adr" 'OpenCode does not publish a Linux PPC64LE binary'
assert_contains "$adr" '`1.18.9-mkchad.3`'
assert_contains "$adr" '`4cdd0b8c77106c4efdca5278f86ffe5e9af8602aedcfca413600bb3abe778b1a`'
assert_contains "$adr" '`211562aa07f70baf178fa2e7726839178a256eef26db1b6651d3ba836b021433`'
assert_contains "$adr" '`1.3.14`'
assert_contains "$adr" '`bun-v1.3.14`'
assert_contains "$adr" '`bun-linux-x64.zip`'
assert_contains "$adr" '`951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f`'
assert_contains "$adr" '`bun-linux-aarch64.zip`'
assert_contains "$adr" '`a27ffb63a8310375836e0d6f668ae17fa8d8d18b88c37c821c65331973a19a3b`'
assert_contains "$adr" 'source authoring and testing'
assert_contains "$adr" 'not required for normal OpenCode runtime'
assert_contains "$adr" 'Keep the x86_64 and aarch64 images at functional parity'
assert_contains "$adr" '| `bubblewrap` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `libtalloc-devel` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `pkgconf-pkg-config` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `musl-gcc` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `musl-devel` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" '| `musl-libc-static` | x86, ARM | Fedora 43 package/update stream |'
assert_contains "$adr" 'Release `v5.4.0`, root commit `bd5a5f63d72f8210d8cee76195eb9f0749e5bd70`'
assert_contains "$adr" 'checked-out submodule commit `e493aa90a2833b4655927598f169c31cfcdf7861`'
assert_contains "$adr" '| `glibc-static` | PPC | Fedora Rawhide package stream |'
assert_contains "$adr" '## Container-Tools Package Delivery'
assert_contains "$adr" '`/opt/msk/container-tools`'
assert_contains "$adr" 'CARE, QEMU, and other PRoot utilities'
assert_contains "$adr" 'are not built or installed.'
assert_contains "$adr" 'installs the executable under `/opt/msk/proot`, and exposes'
assert_contains "$adr" 'it through `/usr/bin/proot`'
assert_contains "$adr" 'The isolated prefix retains the applicable upstream'
assert_contains "$adr" 'PRoot and `lib/uthash` license material.'

bash "$runtime_test" --self-test

: <<'RETIRED_LEGACY_BACKEND_RUNTIME_TEST'
make_bwrap_fixture() {
  local path=$1

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then' \
    '  printf "%s\\n" "${HB_BWRAP_VERSION}"' \
    '  sleep "${HB_BWRAP_VERSION_DELAY:-0}"' \
    '  exit "${HB_BWRAP_VERSION_STATUS:-0}"' \
    'fi' \
    'printf "%s\\n" "$*" >> "${HB_FIXTURE_LOG}"' \
    '[[ $* == "--unshare-user --uid 0 --gid 0 --ro-bind / / --dev /dev --proc /proc -- /bin/true" ]]' \
    'printf "%s\\n" bwrap-operation-stdout' \
    'printf "%s\\n" bwrap-operation-stderr >&2' \
    'if [[ ${HB_BWRAP_IGNORE_TERM:-false} == true ]]; then trap "" TERM; while :; do :; done; fi' \
    'sleep "${HB_BWRAP_DELAY:-0}"' \
    'exit "${HB_BWRAP_STATUS:-0}"' > "$path"
  chmod +x "$path"
}

make_proot_fixture() {
  local path=$1

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then' \
    '  printf "%s\\n" "${HB_PROOT_VERSION}"' \
    '  sleep "${HB_PROOT_VERSION_DELAY:-0}"' \
    '  exit "${HB_PROOT_VERSION_STATUS:-0}"' \
    'fi' \
    'printf "%s\\n" "$*" >> "${HB_FIXTURE_LOG}"' \
    '[[ $* == "-r / /bin/true" ]]' \
    'printf "%s\\n" proot-operation-stdout' \
    'printf "%s\\n" proot-operation-stderr >&2' \
    'if [[ -n ${HB_PROOT_WRITE_PATH:-} ]]; then' \
    '  for ((i = 0; i < 64; i++)); do printf "%1024s" x; done > "${HB_PROOT_WRITE_PATH}"' \
    'fi' \
    'if [[ ${HB_PROOT_IGNORE_TERM:-false} == true ]]; then trap "" TERM; while :; do :; done; fi' \
    'sleep "${HB_PROOT_DELAY:-0}"' \
    'exit "${HB_PROOT_STATUS:-0}"' > "$path"
  chmod +x "$path"
}

make_noisy_version_fixture() {
  local path=$1

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then' \
    '  for ((i = 0; i < 256; i++)); do printf "%4096s" x; done' \
    '  sleep 3' \
    'fi' \
    'exit 0' > "$path"
  chmod +x "$path"
}

assert_runtime_json() {
  local output=$1
  local architecture=$2
  local runtime_kind=$3
  local bwrap_installed=$4
  local bwrap_version_valid=$5
  local bwrap_operational=$6
  local bwrap_reason=$7
  local proot_installed=$8
  local proot_version_valid=$9
  local proot_operational=${10}
  local proot_reason=${11}

  python3 - "$output" "$architecture" "$runtime_kind" \
    "$bwrap_installed" "$bwrap_version_valid" "$bwrap_operational" "$bwrap_reason" \
    "$proot_installed" "$proot_version_valid" "$proot_operational" "$proot_reason" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["schema"] == "container-tools.runtime-evidence/v1"
assert result["architecture"] == sys.argv[2]
assert result["runtime_kind"] == sys.argv[3]
for name, installed, version_valid, operational, reason in (
    ("bubblewrap", sys.argv[4] == "true", sys.argv[5] == "true", sys.argv[6] == "true", sys.argv[7]),
    ("proot", sys.argv[8] == "true", sys.argv[9] == "true", sys.argv[10] == "true", sys.argv[11]),
):
    backend = result["backends"][name]
    assert backend["installed"] is installed
    assert backend["operational"] is operational
    assert backend["reason"] == reason
    assert backend["version_valid"] is version_valid
PY
}

runtime_fixture_dir="$test_tmpdir/selected-root-runtime"
mkdir -p "$runtime_fixture_dir"
bwrap_fixture="$runtime_fixture_dir/bwrap"
proot_fixture="$runtime_fixture_dir/proot"
noisy_version_fixture="$runtime_fixture_dir/noisy-version"
fixture_log="$runtime_fixture_dir/commands"
make_bwrap_fixture "$bwrap_fixture"
make_proot_fixture "$proot_fixture"
make_noisy_version_fixture "$noisy_version_fixture"
proot_version_release=$' _____ _____              ___\n|__|  |__|__\\_____/\\_____/\\____| v5.4.0\n\nbuilt-in accelerators: process_vm = yes, seccomp_filter = yes'
proot_version_pinned=$' _____ _____              ___\n|__|  |__|__\\_____/\\_____/\\____| v5.4.0-bd5a5f63\n\nbuilt-in accelerators: process_vm = yes, seccomp_filter = yes'
case $(uname -m) in
  x86_64|amd64) default_runtime_architecture=x86_64 ;;
  aarch64|arm64) default_runtime_architecture=aarch64 ;;
  *) default_runtime_architecture=unknown ;;
esac

HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_PROOT_VERSION="$proot_version_pinned" \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" \
  --timeout 2 --architecture x86_64 --runtime-kind docker \
  > "$runtime_fixture_dir/valid.stdout" 2> "$runtime_fixture_dir/valid.stderr"
runtime_output=$(<"$runtime_fixture_dir/valid.stdout")
assert_runtime_json "$runtime_output" x86_64 docker true true true operational true true true operational
if [[ -s $runtime_fixture_dir/valid.stderr ]]; then
  printf '%s\n' 'runtime test leaked backend diagnostics for valid operations' >&2
  exit 1
fi
assert_contains "$fixture_log" '--unshare-user --uid 0 --gid 0 --ro-bind / / --dev /dev --proc /proc -- /bin/true'
assert_contains "$fixture_log" '-r / /bin/true'

proot_operation_file="$runtime_fixture_dir/proot-operation-file"
runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_PROOT_VERSION="$proot_version_release" \
  HB_PROOT_WRITE_PATH=$proot_operation_file \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true true operational true true true operational
if [[ ! -s $proot_operation_file ]]; then
  printf '%s\n' 'runtime test constrained backend operation files' >&2
  exit 1
fi

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_BWRAP_STATUS=1 \
  HB_PROOT_VERSION="$proot_version_release" \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" \
  --architecture arm64 --runtime-kind sif)
assert_runtime_json "$runtime_output" aarch64 sif true true false policy-or-runtime-denied true true true operational

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' \
  HB_PROOT_VERSION="$proot_version_release" HB_PROOT_STATUS=1 \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true true operational true true false policy-or-runtime-denied

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_BWRAP_STATUS=1 \
  HB_PROOT_VERSION="$proot_version_release" HB_PROOT_STATUS=1 \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true false policy-or-runtime-denied true true false policy-or-runtime-denied

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_BWRAP_STATUS=124 \
  HB_PROOT_VERSION="$proot_version_release" HB_PROOT_STATUS=137 \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true false policy-or-runtime-denied true true false policy-or-runtime-denied

runtime_output=$("$runtime_test" --bwrap "$runtime_fixture_dir/missing-bwrap" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct false false false missing true false false invalid-version

runtime_output=$("$runtime_test" --bwrap "$runtime_fixture_dir/missing-bwrap" --proot "$runtime_fixture_dir/missing-proot")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct false false false missing false false false missing

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap malformed' HB_PROOT_VERSION='proot stale' \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true false false invalid-version true false false invalid-version

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_BWRAP_DELAY=2 \
  HB_PROOT_VERSION="$proot_version_release" \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" --timeout 1)
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true false timeout true true true operational

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' \
  HB_PROOT_VERSION="$proot_version_release" HB_PROOT_IGNORE_TERM=true \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" --timeout 1)
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true true operational true true false timeout

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' HB_BWRAP_VERSION_DELAY=2 \
  HB_PROOT_VERSION="$proot_version_release" \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" --timeout 1)
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true false false timeout true true true operational

runtime_output=$(HB_FIXTURE_LOG=$fixture_log \
  HB_BWRAP_VERSION='bubblewrap 0.11.0' \
  HB_PROOT_VERSION="$proot_version_release" HB_PROOT_VERSION_DELAY=2 \
  "$runtime_test" --bwrap "$bwrap_fixture" --proot "$proot_fixture" --timeout 1)
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true true true operational true false false timeout

runtime_probe_tmp="$runtime_fixture_dir/tmp"
mkdir -p "$runtime_probe_tmp"
runtime_output=$(TMPDIR=$runtime_probe_tmp HB_FIXTURE_LOG=$fixture_log \
  HB_PROOT_VERSION="$proot_version_release" \
  "$runtime_test" --bwrap "$noisy_version_fixture" --proot "$proot_fixture" --timeout 1 \
  2> "$runtime_fixture_dir/noisy.stderr")
assert_runtime_json "$runtime_output" "$default_runtime_architecture" direct true false false invalid-version true true true operational
if [[ -s $runtime_fixture_dir/noisy.stderr ]]; then
  printf '%s\n' 'runtime test leaked bounded probe diagnostics' >&2
  exit 1
fi
if compgen -G "$runtime_probe_tmp/selected-root-runtime.*" > /dev/null; then
  printf '%s\n' 'runtime test left bounded probe captures behind' >&2
  exit 1
fi

if ! "$runtime_test" --help > "$runtime_fixture_dir/help.stdout" 2> "$runtime_fixture_dir/help.stderr"; then
  printf '%s\n' 'runtime test rejected its help request' >&2
  exit 1
fi
assert_contains "$runtime_fixture_dir/help.stdout" 'Usage:'
if [[ -s $runtime_fixture_dir/help.stderr ]]; then
  printf '%s\n' 'runtime test emitted help diagnostics to stderr' >&2
  exit 1
fi

if "$runtime_test" --timeout zero > "$runtime_fixture_dir/invalid.stdout" 2> "$runtime_fixture_dir/invalid.stderr"; then
  printf '%s\n' 'runtime test accepted malformed timeout override' >&2
  exit 1
else
  invalid_timeout_status=$?
fi
if (( invalid_timeout_status != 2 )); then
  printf 'runtime test returned %s for malformed timeout override\n' "$invalid_timeout_status" >&2
  exit 1
fi
assert_contains "$runtime_fixture_dir/invalid.stderr" 'Usage:'
if [[ -s $runtime_fixture_dir/invalid.stdout ]]; then
  printf '%s\n' 'runtime test emitted JSON for malformed overrides' >&2
  exit 1
fi
if "$runtime_test" --runtime-kind invalid > "$runtime_fixture_dir/unknown.stdout" 2> "$runtime_fixture_dir/unknown.stderr"; then
  printf '%s\n' 'runtime test accepted unknown runtime kind' >&2
  exit 1
else
  invalid_runtime_kind_status=$?
fi
if (( invalid_runtime_kind_status != 2 )); then
  printf 'runtime test returned %s for unknown runtime kind\n' "$invalid_runtime_kind_status" >&2
  exit 1
fi
assert_contains "$runtime_fixture_dir/unknown.stderr" 'Usage:'
if [[ -s $runtime_fixture_dir/unknown.stdout ]]; then
  printf '%s\n' 'runtime test emitted JSON for unknown overrides' >&2
  exit 1
fi
RETIRED_LEGACY_BACKEND_RUNTIME_TEST
printf '%s\n' 'nvim container tooling tests passed'
