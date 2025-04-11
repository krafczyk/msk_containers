#!/bin/bash

docker buildx build --platform linux/x86_64 -f nvim_container_x86.dockerfile -t nvim_container_x86:latest --load .
