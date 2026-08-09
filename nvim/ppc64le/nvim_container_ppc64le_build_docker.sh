#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
context=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/nvim-ppc64le-docker-context.XXXXXX)
trap 'rm -rf -- "$context"' EXIT

container_tools=$("$script_dir/../bin/resolve_container_tools.sh")

cp -a -- "$script_dir/." "$context"
"$script_dir/../bin/stage_container_tools_package.sh" ppc64le "$context"
"$container_tools" buildx exec --architecture ppc64le -- docker buildx build \
    --build-arg "CONTAINER_TOOLS_PACKAGE_SHA256=$(<"$context/container-tools-package.sha256")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_VERSION=$(<"$context/container-tools-package.version")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT=$(<"$context/container-tools-package.source-commit")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_ARCHITECTURE=$(<"$context/container-tools-package.architecture")" \
    --build-arg "CONTAINER_TOOLS_PACKAGE_LIBC=$(<"$context/container-tools-package.libc")" \
    --platform linux/ppc64le -f "$context/nvim_container_ppc64le.dockerfile" \
    -t nvim_container_ppc64le:latest --load "$context"
