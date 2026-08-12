#!/usr/bin/env bash

# Select SingularityCE or fall back to Apptainer. On success, export the
# canonical backend, selected executable, and compatibility TOOL name. Return
# nonzero without side effects when neither backend is available.
nvim_select_container_backend() {
  if NVIM_CONTAINER_RUNTIME_EXECUTABLE=$(command -v singularity 2>/dev/null); then
    NVIM_CONTAINER_RUNTIME=singularity
  elif NVIM_CONTAINER_RUNTIME_EXECUTABLE=$(command -v apptainer 2>/dev/null); then
    NVIM_CONTAINER_RUNTIME=apptainer
  else
    return 1
  fi

  export NVIM_CONTAINER_RUNTIME NVIM_CONTAINER_RUNTIME_EXECUTABLE TOOL=$NVIM_CONTAINER_RUNTIME
}

# Select NVIM_CONT_LOCATION or its HOME-relative default. Return nonzero with a
# diagnostic when the selected image is not a regular file.
nvim_require_container_image() {
  NVIM_CONT_LOCATION=${NVIM_CONT_LOCATION:-"$HOME/containers/neovim.sif"}
  if [[ ! -f $NVIM_CONT_LOCATION ]]; then
    printf 'The container file %s does not exist.\n' "$NVIM_CONT_LOCATION" >&2
    return 1
  fi
}
