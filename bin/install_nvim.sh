#!/usr/bin/env bash

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
bin_dir="$script_dir/../nvim/bin"
target_dir="$HOME/.local/bin"
files=(
  "$bin_dir"/*.sh
  "$bin_dir/nvim"
  "$bin_dir/nvim_shell"
  "$bin_dir/nvim_clear_data"
  "$bin_dir/mkchad"
  "$bin_dir/mkchad-opencode-server"
  "$bin_dir/install_nvim_container"
)

for file in "${files[@]}"; do
  install -Dv -m755 "$file" "$target_dir/${file##*/}"
done
