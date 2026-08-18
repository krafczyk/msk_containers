#!/bin/bash
# shellcheck disable=SC2006

# Check if Singularity is installed
if command -v singularity &> /dev/null; then
    echo "Singularity found. Running Singularity container."
    SINGULARITY=`which singularity`
# If Singularity is not installed, check if Docker is installed
elif command -v apptainer &> /dev/null; then
    echo "Apptainer found. Running Docker container."
    SINGULARITY=`which apptainer`
# If neither Singularity nor Docker is installed, exit with an error message
else
    echo "Neither Singularity nor Apptainer are installed. Please install one of them."
    exit 1
fi

output_sif=${1:-nvim_container_x86.sif}
${SINGULARITY} build --force --fakeroot "$output_sif" nvim_container_x86.def
