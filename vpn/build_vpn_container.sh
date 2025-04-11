#!/usr/bin/env bash
#
# A sample build script for rootless Podman.

# Image name (change as needed)
IMAGE_NAME="vpn_container"

# Image tag (e.g., "latest" or a version number)
IMAGE_TAG="latest"

# By default, when running as a non-root user, Podman stores images and containers
# in ~/.local/share/containers/storage. If you'd like to change this location, see
# the example storage.conf below and place it in ~/.config/containers/storage.conf.

podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f Dockerfile .

# Optionally, run the container to confirm it works:
# podman run --rm -it "${IMAGE_NAME}:${IMAGE_TAG}" /bin/bash
