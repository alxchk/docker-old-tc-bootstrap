#!/bin/sh

set -e

DOCKER_COMMAND=${DOCKER_COMMAND:-docker}

${DOCKER_COMMAND} build --squash -f Dockerfile.buster-wine -t debian:buster-wine

${DOCKER_COMMAND} build --squash -t wine:debian -f Dockerfile.wine-slim .

if [ ! -d MSVCDocker/build/msvc15/snapshots/CMP ]; then
    make -C MSVCDocker WINE_VER=debian MSVC_VERS=15 DOCKERCMD=${DOCKER_COMMAND}
fi

${DOCKER_COMMAND} build --squash -t msvc-slim:15 -f Dockerfile.slim MSVCDocker
