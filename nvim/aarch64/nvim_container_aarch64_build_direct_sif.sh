#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
nvim_dir=$(cd -- "$script_dir/.." && pwd -P)
repo_dir=$(cd -- "$script_dir/../.." && pwd -P)
archive="$script_dir/nvim_container_aarch64.tar"
revision=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
  -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_INDEX_FILE -u GIT_NAMESPACE \
  git -C "$repo_dir" rev-parse --verify 'HEAD^{commit}')
sif="$script_dir/nvim_container_aarch64_g${revision}.sif"

docker buildx build --platform linux/arm64 -f "$script_dir/nvim_container_aarch64.dockerfile" -t nvim_container_aarch64:latest --output "type=docker,dest=$archive" "$nvim_dir"

(
  cd -- "$script_dir"
  bash ./nvim_container_aarch64_build_singularity.sh "$sif"
)
