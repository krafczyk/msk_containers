#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
nvim_dir=$(cd -- "$script_dir/.." && pwd -P)
archive="$script_dir/nvim_container_x86.tar"

docker buildx build --platform linux/x86_64 -f "$script_dir/nvim_container_x86.dockerfile" -t nvim_container_x86:latest --output "type=docker,dest=$archive" "$nvim_dir"

(
  cd -- "$script_dir"
  bash ./nvim_container_x86_build_singularity.sh
)
