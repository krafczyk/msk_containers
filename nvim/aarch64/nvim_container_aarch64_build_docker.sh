#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
nvim_dir=$(realpath "$script_dir/..")
context=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/nvim-aarch64-docker-context.XXXXXX)
trap 'rm -rf -- "$context"' EXIT

container_tools=$("$nvim_dir/bin/resolve_container_tools.sh")

cp -a -- "$nvim_dir/." "$context"
"$nvim_dir/bin/stage_container_tools_package.sh" aarch64 "$context"
"$container_tools" buildx exec --architecture aarch64 -- docker buildx build \
    --build-arg "CONTAINER_TOOLS_PACKAGE_SHA256=$(<"$context/container-tools-package.sha256")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_VERSION=$(<"$context/container-tools-package.version")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT=$(<"$context/container-tools-package.source-commit")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_ARCHITECTURE=$(<"$context/container-tools-package.architecture")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_LIBC=$(<"$context/container-tools-package.libc")" \
    --platform linux/arm64 -f "$context/aarch64/nvim_container_aarch64.dockerfile" \
    -t nvim_container_aarch64:latest --load "$context"
