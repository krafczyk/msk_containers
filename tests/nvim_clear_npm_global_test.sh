#!/usr/bin/env bash

set -euo pipefail

work=${1:?pass a new task-specific directory beneath /tmp/mkchad-v1}
[[ $work == /tmp/mkchad-v1/* ]] || {
  printf '%s\n' 'test directory must be beneath /tmp/mkchad-v1' >&2
  exit 2
}
[[ ! -e $work && ! -L $work ]] || {
  printf '%s\n' 'test directory already exists' >&2
  exit 2
}

repo=$(git rev-parse --show-toplevel)
utility="$repo/nvim/bin/nvim_clear_npm_global"
home="$work/home"
managed="$home/.local/share/msk_containers"
npm_root="$managed/npm-global"
mkdir -p "$npm_root/linux-x64-node24/lib/node_modules/example" "$managed/preserved"
printf '%s\n' package >"$npm_root/linux-x64-node24/lib/node_modules/example/package.json"
printf '%s\n' sibling >"$managed/preserved/value"

dry_run=$(HOME="$home" "$utility" --dry-run)
[[ $dry_run == "Would clear: $npm_root" && -f $npm_root/linux-x64-node24/lib/node_modules/example/package.json ]] || {
  printf '%s\n' 'dry run changed or misreported the npm root' >&2
  exit 1
}

cleared=$(HOME="$home" "$utility")
[[ $cleared == "Cleared: $npm_root" && ! -e $npm_root && ! -L $npm_root ]] || {
  printf '%s\n' 'npm root was not cleared' >&2
  exit 1
}
[[ $(<"$managed/preserved/value") == sibling ]] || {
  printf '%s\n' 'npm root cleanup changed sibling data' >&2
  exit 1
}
[[ $(HOME="$home" "$utility") == "Already clear: $npm_root" ]] || {
  printf '%s\n' 'missing npm root was not an idempotent success' >&2
  exit 1
}

outside="$work/outside"
mkdir "$outside"
printf '%s\n' outside >"$outside/value"
ln -s "$outside" "$npm_root"
set +e
symlink_output=$(HOME="$home" "$utility" 2>&1)
symlink_status=$?
set -e
[[ $symlink_status -ne 0 && $symlink_output == *'symbolic link'* && -L $npm_root && $(<"$outside/value") == outside ]] || {
  printf '%s\n' 'symbolic npm root was not safely rejected' >&2
  exit 1
}
rm "$npm_root"

chmod 775 "$managed"
mkdir "$npm_root"
set +e
mode_output=$(HOME="$home" "$utility" 2>&1)
mode_status=$?
set -e
chmod 755 "$managed"
[[ $mode_status -ne 0 && $mode_output == *'group- or world-writable'* && -d $npm_root ]] || {
  printf '%s\n' 'unsafe managed parent was not rejected' >&2
  exit 1
}

rm -rf "$home/.local/share"
mkdir "$work/share-target"
ln -s "$work/share-target" "$home/.local/share"
set +e
ancestor_output=$(HOME="$home" "$utility" 2>&1)
ancestor_status=$?
set -e
[[ $ancestor_status -ne 0 && $ancestor_output == *'symbolic link'* && -L "$home/.local/share" ]] || {
  printf '%s\n' 'symbolic managed ancestor was not rejected' >&2
  exit 1
}

printf '%s\n' 'nvim_clear_npm_global tests passed'
