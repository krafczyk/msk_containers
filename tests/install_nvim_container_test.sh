#!/usr/bin/env bash
set -euo pipefail

work=${1:?pass a task-specific directory beneath /tmp/opencode-mkchad}
installer=${2:?pass the installer path}
[[ $work == /tmp/opencode-mkchad/* ]] || { printf '%s\n' 'test directory must be beneath /tmp/opencode-mkchad' >&2; exit 2; }
[[ ! -e $work ]] || { printf '%s\n' 'test directory already exists' >&2; exit 2; }

home="$work/home"
fake="$work/fake-bin"
repo="$work/repo"
raw_dir="$repo/nvim/x86"
raw="$raw_dir/nvim_container_x86.sif"
install_dir="$work/containers"
installed_installer="$work/bin/install_nvim_container"
mkdir -p "$home" "$fake" "$raw_dir" "${installed_installer%/*}"

cat > "$fake/apptainer" <<'EOF'
#!/usr/bin/env bash
[[ $1 == exec && $3 == nvim && $4 == --version ]] || exit 64
printf '%s\n' 'NVIM v0.12.4'
EOF
cat > "$fake/uname" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -m ]] || exit 64
printf '%s\n' 'x86_64'
EOF
chmod 755 "$fake/apptainer" "$fake/uname"
install -m755 "$installer" "$installed_installer"

printf '%s\n' 'fixture image' > "$raw"
git -C "$repo" init -q
git -C "$repo" add nvim/x86/nvim_container_x86.sif
git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm 'Add image fixture'
printf '%s\n' 'current revision' > "$repo/revision-marker"
git -C "$repo" add revision-marker
git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm 'Advance current revision'
revision=$(git -C "$repo" rev-parse HEAD)
digest=$(sha256sum "$raw")
digest=${digest%% *}
artifact="neovim_0.12.4_g${revision}_${digest}_x86_64.sif"

decoy="$work/decoy"
mkdir -p "$decoy"
git -C "$decoy" init -q
printf '%s\n' 'decoy revision' > "$decoy/marker"
git -C "$decoy" add marker
git -C "$decoy" -c user.name=Test -c user.email=test@example.invalid commit -qm 'Add decoy fixture'

dry_output=$(HOME="$home" PATH="$fake:$PATH" NVIM_CONTAINER_DIR="$install_dir" \
  GIT_DIR="$decoy/.git" GIT_WORK_TREE="$decoy" \
  "$installed_installer" --dry-run "$raw")
[[ $dry_output == *"Would install: $install_dir/$artifact"* ]] || {
  printf '%s\n' 'dry run did not report the generated managed name' >&2
  exit 1
}
[[ ! -e $install_dir ]] || { printf '%s\n' 'dry run created the install directory' >&2; exit 1; }

HOME="$home" PATH="$fake:$PATH" NVIM_CONTAINER_DIR="$install_dir" \
  "$installed_installer" "$raw" >/dev/null
cmp "$raw" "$install_dir/$artifact"
[[ $(readlink "$install_dir/neovim.sif") == "$artifact" ]] || {
  printf '%s\n' 'generated artifact was not activated' >&2
  exit 1
}

detached="$work/nvim_container_x86.sif"
cp "$raw" "$detached"
set +e
detached_output=$(HOME="$home" PATH="$fake:$PATH" NVIM_CONTAINER_DIR="$work/detached-install" \
  "$installed_installer" --dry-run "$detached" 2>&1)
detached_status=$?
set -e
[[ $detached_status -ne 0 && $detached_output == *'cannot determine repository revision for raw build image'* ]] || {
  printf '%s\n' 'detached raw image did not fail with a revision error' >&2
  exit 1
}

managed_dir="$work/managed-source"
managed_install="$work/managed-install"
mkdir -p "$managed_dir"
managed_digest=$(sha256sum "$raw")
managed_digest=${managed_digest%% *}
managed="$managed_dir/neovim_0.12.4_g1234567_${managed_digest:0:8}_x86.sif"
cp "$raw" "$managed"
cat > "$fake/git" <<'EOF'
#!/usr/bin/env bash
exit 93
EOF
chmod 755 "$fake/git"
HOME="$home" PATH="$fake:$PATH" NVIM_CONTAINER_DIR="$managed_install" \
  "$installed_installer" --no-activate "$managed" >/dev/null
cmp "$managed" "$managed_install/${managed##*/}"
[[ ! -e "$managed_install/neovim.sif" ]] || { printf '%s\n' 'managed no-activate install changed the active link' >&2; exit 1; }

printf '%s\n' 'install_nvim_container tests passed'
