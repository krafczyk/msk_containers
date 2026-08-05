#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
repo_dir=$(realpath "$script_dir/../..")
# shellcheck source=../../container_tools/ct_library.sh
. "$repo_dir/container_tools/ct_library.sh"

configure_docker_build_storage ppc64le
trap discard_docker_build_storage EXIT
docker buildx build --platform linux/ppc64le -f "$script_dir/nvim_container_ppc64le.dockerfile" -t nvim_container_ppc64le:latest "${DOCKER_BUILD_CACHE_ARGS[@]}" --load "$script_dir"
commit_docker_build_storage
trap - EXIT
