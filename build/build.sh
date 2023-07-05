#!/bin/bash

# Build for specific torch because we need to force Hordelib
# and KoboldAI to use the same version to save space.

while getopts t: flag
do
    case "${flag}" in
        t) torch=${OPTARG};;
    esac
done

if [ -z "$torch" ]
then
    torch=2.0.1
fi

printf "Building for torch Version $torch\n";

VER_TAG=torch_${torch}

docker build --progress=plain --build-arg TORCH_VERSION=$torch -t ghcr.io/ai-dock/base-torch:latest -t ghcr.io/ai-dock/base-torch:$VER_TAG . 
#docker push ghcr.io/ai-dock/ai-horde-dreamer:$VER_TAG &&
#docker push ghcr.io/ai-dock/ai-horde-dreamer:latest
