#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

script_dir=$(dirname "$(realpath "$0")")
context=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/nvim-ppc64le-sif-context.XXXXXX)
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

if [[ -n ${CT_ROOT:-} ]]; then
    [[ $CT_ROOT == /* ]] || { printf 'CT_ROOT must be an absolute package bin directory\n' >&2; exit 1; }
    container_tools=$(realpath -e -- "$CT_ROOT/container-tools" 2>/dev/null) || {
        printf 'container-tools executable is not usable beneath CT_ROOT: %s\n' "$CT_ROOT" >&2
        exit 1
    }
else
    container_tools=$(command -v container-tools) || {
        printf 'container-tools executable was not found on PATH\n' >&2
        exit 1
    }
fi

if [[ ! -f $container_tools || ! -x $container_tools ]] || ! "$container_tools" package verify >/dev/null; then
    printf 'container-tools executable is not a complete package: %s\n' "$container_tools" >&2
    exit 1
fi

cp -a -- "$script_dir/." "$context"
"$script_dir/../bin/stage_container_tools_package.sh" ppc64le "$context"
(
    cd "$context"
    "$container_tools" runtime exec --backend "${SINGULARITY##*/}" -- "$SINGULARITY" build --force --fakeroot "$script_dir/nvim_container_ppc64le.sif" nvim_container_ppc64le.def
)
