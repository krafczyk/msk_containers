#!/usr/bin/env bash
set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
nvim_dir=$(realpath "$script_dir/..")
docker buildx build --platform linux/arm64 -f "$nvim_dir/aarch64/nvim_container_aarch64.dockerfile" -t nvim_container_aarch64:latest --load "$nvim_dir"
