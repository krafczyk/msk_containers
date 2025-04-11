#!/bin/bash

docker buildx build --platform linux/ppc64le -f nvim_container_ppc64le.dockerfile -t nvim_container_ppc64le:latest --load .
