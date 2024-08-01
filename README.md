[![Docker Build](https://github.com/ai-dock/base-image/actions/workflows/docker-build.yml/badge.svg)](https://github.com/ai-dock/base-image/actions/workflows/docker-build.yml)

# Base Image

All ai-dock images are extended from this base image.

This file should form the basis for the README.md for all extended images, with nothing but this introduction removed and additional features documented as required.

## Documentation

All AI-Dock containers share a common base which is designed to make running on container-first cloud services such as [vast.ai](https://link.ai-dock.org/vast.ai) as straightforward and user friendly as possible.

Common features and options are documented in the [base wiki](https://github.com/ai-dock/base-image/wiki) but any additional features unique to this image will be detailed below.

## Pre-built Images

Docker images are built automatically through a GitHub Actions workflow and hosted at the GitHub Container Registry.

#### Version Tags

There is no `latest` tag.
Tags follow these patterns:

##### _CUDA_
`:v2-cuda-[x.x.x]{-cudnn[x]}-[base|runtime|devel]-[ubuntu-version]`

##### _ROCm_
`:v2-rocm-[x.x.x]-[core|runtime|devel]-[ubuntu-version]`

ROCm builds are experimental. Please give feedback.

##### _CPU_
`:v2-cpu-[ubuntu-version]`

Browse [here](https://github.com/ai-dock/base-image/pkgs/container/base-image) for an image suitable for your target environment.

---

_The author ([@robballantyne](https://github.com/robballantyne)) may be compensated if you sign up to services linked in this document. Testing multiple variants of GPU images in many different environments is both costly and time-consuming; This helps to offset costs_