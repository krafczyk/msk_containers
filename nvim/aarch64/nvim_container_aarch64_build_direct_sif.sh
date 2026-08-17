#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
nvim_dir=$(cd -- "$script_dir/.." && pwd -P)
archive="$script_dir/nvim_container_aarch64.tar"

docker buildx build --platform linux/arm64 -f "$script_dir/nvim_container_aarch64.dockerfile" -t nvim_container_aarch64:latest --output "type=docker,dest=$archive" "$nvim_dir"

(
  cd -- "$script_dir"
  bash ./nvim_container_aarch64_build_singularity.sh
)
