#!/usr/bin/env bash
# Characterize native image-builder invocation and definition-owned tool builds.
# shellcheck disable=SC2016
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
revision=404abbed85953875edd83309a4473517449cb5d3
ppc_revision=$revision
work=$(mktemp -d /tmp/mkchad-v1/container-tools-runtime-boundary/nvim-tooling.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1 expected=$2
  grep -Fq -- "$expected" "$file" || fail "missing $expected in $file"
}

assert_not_contains() {
  local file=$1 unexpected=$2
  if grep -Fq -- "$unexpected" "$file"; then
    fail "unexpected $unexpected in $file"
  fi
}

assert_no_image_wrapper_references() {
  local file
  for file in "$repo"/nvim/{x86,aarch64,ppc64le}/nvim_container_*_{build_docker,build_singularity}.sh; do
    assert_not_contains "$file" container-tools
    assert_not_contains "$file" CT_ROOT
    assert_not_contains "$file" ct_library.sh
    assert_not_contains "$file" buildx\ exec
    assert_not_contains "$file" runtime\ exec
    assert_not_contains "$file" --cache-from
    assert_not_contains "$file" --cache-to
    assert_not_contains "$file" TMPDIR
  done
  [[ ! -e $repo/nvim/bin/resolve_container_tools.sh ]] || fail 'image resolver remains'
  [[ ! -e $repo/nvim/bin/stage_container_tools_package.sh ]] || fail 'image package stager remains'
}

make_builder() {
  local path=$1 name=$2
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s" "${0##*/}" >> "$NVIM_TOOLING_LOG"' \
    'for argument in "$@"; do printf " <%s>" "$argument" >> "$NVIM_TOOLING_LOG"; done' \
    'printf "\n" >> "$NVIM_TOOLING_LOG"' > "$path/$name"
  chmod +x "$path/$name"
}

assert_builder_commands() {
  local bin="$work/builders" log="$work/commands" trap_root="$work/trap"
  local architecture image docker_script singularity_script expected
  mkdir -p "$bin" "$trap_root"
  make_builder "$bin" docker
  make_builder "$bin" singularity
  make_builder "$bin" apptainer
  printf '%s\n' '#!/usr/bin/env bash' 'exit 97' > "$bin/container-tools"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 98' > "$trap_root/container-tools"
  chmod +x "$bin/container-tools" "$trap_root/container-tools"

  for architecture in x86 aarch64 ppc64le; do
    image=nvim_container_$architecture
    docker_script="$repo/nvim/$architecture/${image}_build_docker.sh"
    singularity_script="$repo/nvim/$architecture/${image}_build_singularity.sh"
    if [[ $architecture == ppc64le ]]; then
      (
        cd "$repo/nvim/$architecture"
        NVIM_TOOLING_LOG=$log CT_ROOT=$trap_root PATH="$bin:$PATH" bash "$docker_script"
      )
      expected="docker <buildx> <build> <--platform> <linux/ppc64le> <-f> <nvim_container_ppc64le.dockerfile> <-t> <nvim_container_ppc64le:latest> <--load> <.>"
    else
      (
        cd "$repo/nvim/$architecture"
        NVIM_TOOLING_LOG=$log CT_ROOT=$trap_root PATH="$bin:$PATH" bash "$docker_script"
      )
      if [[ $architecture == x86 ]]; then
        expected="docker <buildx> <build> <--platform> <linux/x86_64> <-f> <$repo/nvim/x86/nvim_container_x86.dockerfile> <-t> <nvim_container_x86:latest> <--load> <$repo/nvim>"
      else
        expected="docker <buildx> <build> <--platform> <linux/arm64> <-f> <$repo/nvim/aarch64/nvim_container_aarch64.dockerfile> <-t> <nvim_container_aarch64:latest> <--load> <$repo/nvim>"
      fi
    fi
    [[ $(<"$log") == "$expected" ]] || fail "unexpected Docker invocation for $architecture: $(<"$log")"
    : > "$log"

    (
      cd "$repo/nvim/$architecture"
      NVIM_TOOLING_LOG=$log CT_ROOT=$trap_root PATH="$bin:$PATH" bash "$singularity_script" > "$work/$architecture.out"
    )
    expected="singularity <build> <--force> <--fakeroot> <${image}.sif> <${image}.def>"
    [[ $(<"$log") == "$expected" ]] || fail "unexpected Singularity invocation for $architecture: $(<"$log")"
    assert_contains "$work/$architecture.out" 'Singularity found. Running Singularity container.'
    : > "$log"
  done

  rm "$bin/singularity"
  (
    cd "$repo/nvim/x86"
    NVIM_TOOLING_LOG=$log CT_ROOT=$trap_root PATH="$bin:$PATH" bash ./nvim_container_x86_build_singularity.sh > "$work/apptainer.out"
  )
  [[ $(<"$log") == 'apptainer <build> <--force> <--fakeroot> <nvim_container_x86.sif> <nvim_container_x86.def>' ]] ||
    fail 'Apptainer fallback did not use the original direct invocation'
  assert_contains "$work/apptainer.out" 'Apptainer found. Running Docker container.'

  if PATH="$work/empty" /bin/bash "$repo/nvim/x86/nvim_container_x86_build_singularity.sh" > "$work/missing.out" 2>&1; then
    fail 'Singularity script accepted a missing native builder'
  fi
  assert_contains "$work/missing.out" 'Neither Singularity nor Apptainer are installed'
}

assert_definition_owned_builds() {
  local architecture dockerfile definition compiler expected_revision pin
  local -a pins=()
  for architecture in x86 aarch64 ppc64le; do
    dockerfile="$repo/nvim/$architecture/nvim_container_${architecture}.dockerfile"
    definition="$repo/nvim/$architecture/nvim_container_${architecture}.def"
    compiler=musl-gcc
    expected_revision=$revision
    if [[ $architecture == ppc64le ]]; then
      compiler=gcc
      expected_revision=$ppc_revision
    fi
    assert_contains "$dockerfile" 'https://github.com/krafczyk/container_tools.git'
    assert_contains "$dockerfile" "git -C /tmp/container-tools checkout --detach $expected_revision"
    assert_contains "$dockerfile" "test \"\$(git -C /tmp/container-tools rev-parse HEAD)\" = $expected_revision"
    assert_contains "$dockerfile" "-D CMAKE_C_COMPILER=$compiler"
    assert_contains "$dockerfile" 'cmake --build /tmp/container-tools-build'
    assert_contains "$dockerfile" 'cmake --install /tmp/container-tools-build --prefix /opt/msk/container-tools'
    assert_contains "$dockerfile" 'ENV PATH="/opt/msk/container-tools/bin:$PATH"'
    assert_contains "$dockerfile" 'container-tools --version --json'
    assert_contains "$dockerfile" '"mount_plan_grammar":"ct-mount-plan-v1"'
    assert_contains "$dockerfile" 'rm -rf /tmp/container-tools /tmp/container-tools-build'
    assert_not_contains "$dockerfile" 'ARG CONTAINER_TOOLS'
    assert_not_contains "$dockerfile" 'container-tools-package'
    assert_not_contains "$dockerfile" 'package verify'
    assert_not_contains "$definition" '%files'
    assert_not_contains "$definition" '%post'
    assert_not_contains "$definition" 'container-tools-package'
    assert_not_contains "$definition" '/opt/msk/container-tools/bin'
    pin=$(grep -Eo 'checkout --detach [0-9a-f]{40}' "$dockerfile" | awk '{print $3}')
    [[ $pin == "$expected_revision" ]] || fail "Dockerfile pin drifted for $architecture"
    pins+=("$pin")
  done
  [[ ${pins[0]} == "${pins[1]}" ]] || fail 'x86 and aarch64 Dockerfile pins differ'
}

assert_documentation() {
  local adr="$repo/docs/adr/002-package-selections.md"
  local host_installation="$repo/docs/host-installation.md"
  assert_contains "$adr" '## Container-Tools Image Build'
  assert_contains "$adr" "$revision"
  assert_contains "$adr" "$ppc_revision"
  assert_contains "$adr" 'does not inject cache arguments or prune'
  assert_not_contains "$adr" '## Container-Tools Package Delivery'
  assert_not_contains "$adr" resolve_container_tools.sh
  assert_not_contains "$adr" stage_container_tools_package.sh
  assert_contains "$host_installation" '## Image Construction'
  assert_contains "$host_installation" 'Image construction never selects a host `container-tools`'
}

assert_no_image_wrapper_references
assert_builder_commands
assert_definition_owned_builds
assert_documentation
printf '%s\n' 'nvim container tooling tests passed'
