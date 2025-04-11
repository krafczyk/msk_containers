#!/bin/bash

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

${SINGULARITY} build --force --fakeroot nvim_container_ppc64le.sif nvim_container_ppc64le.def
