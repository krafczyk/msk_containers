set -e
bash ./nvim_container_x86_build_docker.sh
bash ./nvim_container_x86_export_docker.sh
bash ./nvim_container_x86_build_singularity.sh
