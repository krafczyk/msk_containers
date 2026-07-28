#!/usr/bin/env bash
# Assertions intentionally match literal Dockerfile shell expressions.
# shellcheck disable=SC2016
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
adr="$repo/docs/adr/002-package-selections.md"

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

normalized_dockerfile() {
  local file=$1
  local luals_build=$2
  local content

  content=$(<"$file")
  content=${content/"$luals_build"/__ARCHITECTURE_SPECIFIC_LUALS_BUILD__}
  content=${content//linux-x64/linux-CONTAINER_ARCH}
  content=${content//linux-arm64/linux-CONTAINER_ARCH}
  printf '%s' "$content"
}

normalized_definition() {
  local file=$1
  local content

  content=$(<"$file")
  content=${content//nvim_container_x86/nvim_container_ARCH}
  content=${content//nvim_container_aarch64/nvim_container_ARCH}
  printf '%s' "$content"
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
x86_definition="$repo/nvim/x86/nvim_container_x86.def"
arm_definition="$repo/nvim/aarch64/nvim_container_aarch64.def"

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
assert_active "$arm" 'node-v${NODE_VER}-linux-arm64.tar.gz'
assert_active "$arm" 'ENV PATH="/nvim/node-v${NODE_VER}-linux-arm64/bin:$PATH"'
assert_not_contains "$arm" 'node-v${NODE_VER}-linux-x64'
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

assert_same_arguments 'dnf install -y ' 'direct DNF package'
assert_same_arguments 'pip3 install --prefix /usr ' 'direct pip package'
assert_same_arguments 'npm install -g basedpyright ' 'global npm package'
assert_same_arguments 'npm install --prefix /opt/msk/browser-tools --save-exact ' 'browser npm package'

for dockerfile in "$x86" "$arm"; do
  assert_active "$dockerfile" 'FROM quay.io/fedora/fedora:43@sha256:d9c079f2727706bfe335fefae57c7518a84e97daf4b1bf9d50fb3e8a75e7e78c'
  assert_active "$dockerfile" 'ENV NODE_VER=24.18.0'
  assert_active "$dockerfile" 'ARG STYLUA_VERSION=2.5.2'
  assert_active "$dockerfile" 'ARG LUACHECK_VERSION=1.2.0-1'
  assert_active "$dockerfile" 'selenium==4.46.0'
  assert_active "$dockerfile" 'py-spy'
  assert_active "$dockerfile" 'ENV JDTLS_MILESTONE=1.56.0'
  assert_active "$dockerfile" 'test -x /nvim/jdtls/bin/jdtls'
  assert_not_contains "$dockerfile" '--strip-components=1'
  assert_active "$dockerfile" 'git clone --depth 1 --branch v2.1-agentzh https://github.com/openresty/luajit2'
  assert_active "$dockerfile" 'git clone --depth 1 --branch v0.12.4 https://github.com/neovim/neovim'
  assert_active "$dockerfile" '-DUSE_BUNDLED=ON'
  assert_active "$dockerfile" '-DUSE_BUNDLED_LUAJIT=OFF'
  assert_active "$dockerfile" 'git clone --depth 1 --branch 3.17.1 https://github.com/LuaLS/lua-language-server'
  assert_active "$dockerfile" 'npm install -g neovim'
  assert_active "$dockerfile" 'ARG OPENCODE_VERSION=1.18.3-mkchad.1'
  assert_active "$dockerfile" 'ARG OPENCODE_REVISION=ec97b6e774d9542b78a8b1b71890233f85f7c297'
  assert_active "$dockerfile" 'ARG BUN_VERSION=1.3.14'
  assert_active "$dockerfile" 'git clone --filter=blob:none https://github.com/krafczyk/opencode.git /nvim/opencode'
  assert_active "$dockerfile" 'git checkout --detach "${OPENCODE_REVISION}"'
  assert_active "$dockerfile" 'bun run build --single --skip-install'
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
done

assert_active "$arm" 'git submodule update --init --recursive'
assert_active "$arm" './compile/build.sh'
assert_active "$arm" '3rd/luamake/luamake all'
assert_active "$x86" 'bash ./make.sh'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'agent-browser'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'opencode-ai'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_VERSION'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_REVISION'

assert_contains "$adr" '| `ffmpeg-free` | All |'
assert_contains "$adr" '| `ShellCheck` | All |'
assert_contains "$adr" '| `jsonschema` | All | `>=4.23,<5` |'
assert_contains "$adr" '| ast-grep | All | Cargo crate pinned to `0.44.1` with `--locked` |'
assert_contains "$adr" '| `agent-browser` | x86, ARM | Pinned to `0.32.2` |'
assert_contains "$adr" '| x86_64 | `24.18.0` | `linux-x64` |'
assert_contains "$adr" '| aarch64 | `24.18.0` | `linux-arm64` |'
assert_contains "$adr" '`linux-x64-node24`'
assert_contains "$adr" 'OpenCode does not publish a Linux PPC64LE binary'
assert_contains "$adr" '`ec97b6e774d9542b78a8b1b71890233f85f7c297`'
assert_contains "$adr" '`1.18.3-mkchad.1`'
assert_contains "$adr" 'Keep the x86_64 and aarch64 images at functional parity'

printf '%s\n' 'nvim container tooling tests passed'
