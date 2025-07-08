# Check if Singularity is installed
if command -v singularity &> /dev/null; then
    echo "Singularity found. Running Singularity container."
    export TOOL="singularity"
# If Singularity is not installed, check if Docker is installed
elif command -v apptainer &> /dev/null; then
    echo "Apptainer found. Running Docker container."
    export TOOL="apptainer"
# If neither Singularity nor Docker is installed, exit with an error message
else
    echo "Neither Singularity nor Apptainer are installed. Please install one of them."
    exit 1
fi

NVIM_CONT_LOCATION="${NVIM_CONT_LOCATION:=${HOME}/containers/neovim.sif}"
# Check if the file $NVIM_CONT_LOCATION exists
if [ ! -f $NVIM_CONT_LOCATION ]; then
  # Present an error message and exit if the file does not exist
  echo "The container file $NVIM_CONT_LOCATION does not exist."
  exit 1
fi
