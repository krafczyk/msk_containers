set -e
bash ./nvim_container_ppc64le_build_docker.sh
bash ./nvim_container_ppc64le_export_docker.sh
bash ./nvim_container_ppc64le_build_singularity.sh
