#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
repo_dir=$(realpath "$script_dir/../..")
# shellcheck source=../../container_tools/ct_library.sh
. "$repo_dir/container_tools/ct_library.sh"

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

configure_runtime_storage "${SINGULARITY##*/}"
"$SINGULARITY" build --force --fakeroot nvim_container_aarch64.sif nvim_container_aarch64.def
