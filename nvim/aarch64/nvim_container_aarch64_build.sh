set -e
bash ./nvim_container_aarch64_build_docker.sh
bash ./nvim_container_aarch64_export_docker.sh
bash ./nvim_container_aarch64_build_singularity.sh
