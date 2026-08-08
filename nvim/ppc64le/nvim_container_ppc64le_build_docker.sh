#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
context=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/nvim-ppc64le-docker-context.XXXXXX)
trap 'rm -rf -- "$context"' EXIT

if [[ -n ${CT_ROOT:-} ]]; then
    [[ $CT_ROOT == /* ]] || { printf 'CT_ROOT must be an absolute package bin directory\n' >&2; exit 1; }
    container_tools=$(realpath -e -- "$CT_ROOT/container-tools" 2>/dev/null) || {
        printf 'container-tools executable is not usable beneath CT_ROOT: %s\n' "$CT_ROOT" >&2
        exit 1
    }
else
    container_tools=$(command -v container-tools) || {
        printf 'container-tools executable was not found on PATH\n' >&2
        exit 1
    }
fi

if [[ ! -f $container_tools || ! -x $container_tools ]] || ! "$container_tools" package verify >/dev/null; then
    printf 'container-tools executable is not a complete package: %s\n' "$container_tools" >&2
    exit 1
fi

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
