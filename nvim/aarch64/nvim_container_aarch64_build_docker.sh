#!/bin/bash

docker buildx build --platform linux/arm64 -f nvim_container_aarch64.dockerfile -t nvim_container_aarch64:latest --load .
