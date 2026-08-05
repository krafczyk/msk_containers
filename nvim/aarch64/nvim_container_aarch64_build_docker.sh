#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
nvim_dir=$(realpath "$script_dir/..")
repo_dir=$(realpath "$nvim_dir/..")
# shellcheck source=../../container_tools/ct_library.sh
. "$repo_dir/container_tools/ct_library.sh"

configure_docker_build_storage aarch64
trap discard_docker_build_storage EXIT
docker buildx build --platform linux/arm64 -f "$nvim_dir/aarch64/nvim_container_aarch64.dockerfile" -t nvim_container_aarch64:latest "${DOCKER_BUILD_CACHE_ARGS[@]}" --load "$nvim_dir"
commit_docker_build_storage
trap - EXIT
