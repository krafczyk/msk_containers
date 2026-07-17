#!/usr/bin/env bash
set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
bin_dir="$script_dir/../container_tools"
target_dir="$HOME/.local/bin"

for file in "$bin_dir"/*.sh; do
  install -Dv -m755 "$file" "$target_dir/${file##*/}"
done
