#!/usr/bin/env bash
# Characterize native image-builder invocation and definition-owned tool builds.
# shellcheck disable=SC2016
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
revision=404abbed85953875edd83309a4473517449cb5d3
ppc_revision=$revision
head_revision=$(git -C "$repo" rev-parse HEAD)
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

assert_exact_line_count() {
  local file=$1 line=$2 expected=$3 actual
  actual=$(grep -Fxc -- "$line" "$file" || true)
  [[ $actual == "$expected" ]] || fail "expected $expected exact lines for $line in $file, found $actual"
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
  local bin="$work/builders" log="$work/commands" trap_root="$work/trap" ambient_git="$work/ambient-git"
  local architecture image docker_script direct_sif_script singularity_script expected platform
  mkdir -p "$bin" "$trap_root"
  make_builder "$bin" docker
  make_builder "$bin" singularity
  make_builder "$bin" apptainer
  printf '%s\n' '#!/usr/bin/env bash' 'exit 97' > "$bin/container-tools"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 98' > "$trap_root/container-tools"
  chmod +x "$bin/container-tools" "$trap_root/container-tools"
  git init -q "$ambient_git"
  git -C "$ambient_git" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm ambient

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

  make_builder "$bin" singularity
  : > "$log"
  for architecture in x86 aarch64; do
    image=nvim_container_$architecture
    if [[ $architecture == x86 ]]; then
      platform=linux/x86_64
    else
      platform=linux/arm64
    fi
    direct_sif_script="$repo/nvim/$architecture/${image}_build_direct_sif.sh"
    (
      cd "$work"
      GIT_DIR="$ambient_git/.git" GIT_WORK_TREE="$ambient_git" GIT_COMMON_DIR="$ambient_git/.git" \
        GIT_OBJECT_DIRECTORY="$ambient_git/.git/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$ambient_git/.git/objects" \
        GIT_INDEX_FILE="$ambient_git/.git/index" GIT_NAMESPACE=ambient \
        NVIM_TOOLING_LOG=$log CT_ROOT=$trap_root PATH="$bin:$PATH" bash "$direct_sif_script"
    )
    assert_not_contains "$log" '<--load>'
    assert_not_contains "$log" 'docker <save>'
    expected="docker <buildx> <build> <--platform> <$platform> <-f> <$repo/nvim/$architecture/${image}.dockerfile> <-t> <${image}:latest> <--output> <type=docker,dest=$repo/nvim/$architecture/${image}.tar> <$repo/nvim>
singularity <build> <--force> <--fakeroot> <$repo/nvim/$architecture/${image}_g${head_revision}.sif> <${image}.def>"
    [[ $(<"$log") == "$expected" ]] || fail "unexpected direct SIF builder invocations for $architecture: $(<"$log")"
    : > "$log"
  done
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

assert_browser_tooling() {
  local architecture dockerfile x86_block arm_block
  for architecture in x86 aarch64; do
    dockerfile="$repo/nvim/$architecture/nvim_container_${architecture}.dockerfile"
    assert_exact_line_count "$dockerfile" "    xdg-utils ffmpeg-free chromium chromium-headless chromedriver \\" 1
    assert_exact_line_count "$dockerfile" 'ARG PLAYWRIGHT_VERSION=1.61.1' 1
    assert_exact_line_count "$dockerfile" 'ARG OPENCODE_PLAYWRIGHT_VERSION=1.59.1' 1
    assert_exact_line_count "$dockerfile" 'ENV PLAYWRIGHT_BROWSERS_PATH=/opt/msk/playwright-browsers' 1
    assert_exact_line_count "$dockerfile" "    npm install --prefix /opt/msk/opencode-playwright --save-exact \\" 1
    assert_exact_line_count "$dockerfile" "       \"@playwright/test@\${OPENCODE_PLAYWRIGHT_VERSION}\" && \\" 1
    assert_exact_line_count "$dockerfile" "    playwright install chromium && \\" 1
    assert_exact_line_count "$dockerfile" \
      "    /opt/msk/opencode-playwright/node_modules/.bin/playwright install chromium && \\" 1
  done

  x86_block=$(awk '/^ARG AGENT_BROWSER_VERSION=/{capture=1} capture{print} /agent-browser --version/{exit}' \
    "$repo/nvim/x86/nvim_container_x86.dockerfile")
  arm_block=$(awk '/^ARG AGENT_BROWSER_VERSION=/{capture=1} capture{print} /agent-browser --version/{exit}' \
    "$repo/nvim/aarch64/nvim_container_aarch64.dockerfile")
  [[ $x86_block == "$arm_block" ]] || fail 'x86 and aarch64 browser tooling blocks differ'
}

line_number() {
  local file=$1 marker=$2 line
  line=$(grep -n -m 1 -F -- "$marker" "$file") || fail "missing $marker in $file"
  printf '%s\n' "${line%%:*}"
}

assert_cache_order() {
  local architecture dockerfile dnf container_path nvim_root luajit neovim luals cargo python node bun jdtls jdtls_path luals_path browser container_tools opencode manifest
  for architecture in x86 aarch64; do
    dockerfile="$repo/nvim/$architecture/nvim_container_${architecture}.dockerfile"
    dnf=$(line_number "$dockerfile" 'RUN dnf update -y')
    container_path=$(line_number "$dockerfile" 'ENV PATH="/opt/msk/container-tools/bin:$PATH"')
    nvim_root=$(line_number "$dockerfile" 'RUN mkdir -p /nvim /opt/msk/npm-global')
    luajit=$(line_number "$dockerfile" '# Build/install LuaJit')
    neovim=$(line_number "$dockerfile" '# Clone neovim')
    luals=$(line_number "$dockerfile" '# Install lua language server')
    cargo=$(line_number "$dockerfile" 'ARG STYLUA_VERSION=')
    python=$(line_number "$dockerfile" '# Install needed python packages')
    node=$(line_number "$dockerfile" 'ENV NODE_VER=')
    bun=$(line_number "$dockerfile" '# Bun supports source authoring and testing; OpenCode uses its verified release.')
    jdtls=$(line_number "$dockerfile" '# Install Eclipse JDTLS')
    jdtls_path=$(line_number "$dockerfile" 'ENV PATH=/nvim/jdtls/bin:$PATH')
    luals_path=$(line_number "$dockerfile" 'ENV PATH="/nvim/lua-language-server/bin:$PATH"')
    browser=$(line_number "$dockerfile" 'ARG AGENT_BROWSER_VERSION=0.32.2')
    container_tools=$(line_number "$dockerfile" '# Build/install container-tools')
    opencode=$(line_number "$dockerfile" 'ARG OPENCODE_VERSION=')
    manifest=$(line_number "$dockerfile" 'COPY component-manifest.json /usr/share/mkchad/component-manifest.json')
    (( dnf < container_path && container_path < nvim_root && nvim_root < luajit &&
       luajit < neovim && neovim < luals &&
       luals < jdtls && jdtls < cargo && cargo < python && python < node &&
       node < jdtls_path && jdtls_path < luals_path && luals_path < browser && browser < bun &&
       bun < container_tools &&
       container_tools < opencode && opencode < manifest )) ||
      fail "unexpected Docker layer cache order for $architecture"
  done
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
  assert_contains "$adr" 'OpenCode Playwright compatibility package'
  assert_contains "$adr" '`@playwright/test` pinned to `1.59.1`'
  assert_contains "$host_installation" '## Image Construction'
  assert_contains "$host_installation" 'Image construction never selects a host `container-tools`'
  assert_contains "$host_installation" 'nvim/x86/nvim_container_x86_build_direct_sif.sh'
  assert_contains "$host_installation" 'nvim/aarch64/nvim_container_aarch64_build_direct_sif.sh'
  assert_contains "$host_installation" 'nvim_container_x86_g<FULL_SHA>.sif'
  assert_contains "$host_installation" 'nvim_container_aarch64_g<FULL_SHA>.sif'
}

assert_no_image_wrapper_references
assert_builder_commands
assert_definition_owned_builds
assert_browser_tooling
assert_cache_order
assert_documentation
printf '%s\n' 'nvim container tooling tests passed'
