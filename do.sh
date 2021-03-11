#!/bin/bash

SELF=${0}
SELFDIR=`dirname "${SELF}"`

IMAGES=(
    "msvc-slim:15"
    "wine:debian"
    "debian:buster-wine"
    "linux-amd64:etch"
    "linux-i386:etch"
    "linux-i386:woody"
)

DOCKER_COMMAND=${DOCKER_COMMAND:-docker}
DOCKER_REPO=${DOCKER_REPO:-alxchk}

case ${1} in
    build)
	for ditem in ${SELFDIR}/*; do
	    if [ ! -d "${ditem}" ]; then
		continue
	    fi

	    (
		cd ${ditem}
		DOCKER_COMMAND=${DOCKER_COMMAND} ./bootstrap.sh
		cd -
	    )
	done
	;;

    publish)
	for image in ${IMAGES[*]}; do
	    echo "Pushing ${image} to ${DOCKER_REPO}/${image}"
	    ${DOCKER_COMMAND} push "${image}" "${DOCKER_REPO}/${image}" || \
		echo "Failed to push ${image} as ${DOCKER_REPO}/${image}"
	done
	;;
    
    *)
	echo "Usage: $0 build|publish"
	;;
esac
