#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
context=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/nvim-aarch64-sif-context.XXXXXX)
trap 'rm -rf -- "$context"' EXIT

if command -v singularity &> /dev/null; then
    echo "Singularity found. Running Singularity container."
    SINGULARITY=$(command -v singularity)
elif command -v apptainer &> /dev/null; then
    echo "Apptainer found. Running Docker container."
    SINGULARITY=$(command -v apptainer)
else
    echo "Neither Singularity nor Apptainer are installed. Please install one of them."
    exit 1
fi

container_tools=$("$script_dir/../bin/resolve_container_tools.sh")

cp -a -- "$script_dir/." "$context"
"$script_dir/../bin/stage_container_tools_package.sh" aarch64 "$context"
(
    cd "$context"
    "$container_tools" runtime exec --backend "${SINGULARITY##*/}" -- "$SINGULARITY" build --force --fakeroot "$script_dir/nvim_container_aarch64.sif" nvim_container_aarch64.def
)
