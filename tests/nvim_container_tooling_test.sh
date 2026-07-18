#!/usr/bin/env bash
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

  grep -Ev '^[[:space:]]*(#|$)' "$file" | grep -F -- "$expected" >/dev/null || {
    printf 'missing active %q in %s\n' "$expected" "$file" >&2
    exit 1
  }
}

assert_not_contains() {
  local file=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" "$file"; then
    printf 'unexpected %q in %s\n' "$unexpected" "$file" >&2
    exit 1
  fi
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
assert_active "$x86" 'ENV NODE_VER=24.18.0'
assert_active "$x86" 'ARG OPENCODE_VERSION=1.18.3'
assert_active "$x86" 'opencode --version'
assert_active "$x86" 'ARG AGENT_BROWSER_VERSION=0.32.2'
assert_active "$x86" 'ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium-browser'
assert_active "$x86" '"agent-browser@${AGENT_BROWSER_VERSION}"'
assert_active "$x86" 'agent-browser --version'
assert_not_contains "$x86" 'agent-browser install'

assert_not_contains "$repo/nvim/aarch64/nvim_container_aarch64.dockerfile" 'agent-browser'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'agent-browser'
assert_active "$repo/nvim/aarch64/nvim_container_aarch64.dockerfile" 'ARG OPENCODE_VERSION=1.18.3'
assert_active "$repo/nvim/aarch64/nvim_container_aarch64.dockerfile" 'opencode --version'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'opencode-ai'
assert_not_contains "$repo/nvim/ppc64le/nvim_container_ppc64le.dockerfile" 'OPENCODE_VERSION'

assert_contains "$adr" '| `ffmpeg-free` | All |'
assert_contains "$adr" '| `ShellCheck` | All |'
assert_contains "$adr" '| `jsonschema` | All | `>=4.23,<5` |'
assert_contains "$adr" '| ast-grep | All | Cargo crate pinned to `0.44.1` with `--locked` |'
assert_contains "$adr" '| `agent-browser` | x86 | Pinned to `0.32.2` |'
assert_contains "$adr" '| x86_64 | `24.18.0` | `linux-x64` |'
assert_contains "$adr" '`linux-x64-node24`'
assert_contains "$adr" 'OpenCode does not publish a Linux PPC64LE binary'

printf '%s\n' 'nvim container tooling tests passed'
