#!/usr/bin/env bash

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
nvim_dir=$(realpath "$script_dir/..")
docker buildx build --platform linux/x86_64 -f "$nvim_dir/x86/nvim_container_x86.dockerfile" -t nvim_container_x86:latest --load "$nvim_dir"
