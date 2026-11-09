#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IMAGE=${IMAGE:-arch-orb:latest}
AMP_IMAGE=${AMP_IMAGE:-us-central1-docker.pkg.dev/amp-prod-0/amp-orb/amp-orb:latest}
ARCH_MIRROR=${ARCH_MIRROR:-https://geo.mirror.pkgbuild.com}
ARCHLINUXCN_MIRROR=${ARCHLINUXCN_MIRROR:-https://repo.archlinuxcn.org}
BASE_IMAGE=${BASE_IMAGE:-quay.io/archlinux/archlinux:latest}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}

if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
	echo "error: $CONTAINER_ENGINE is required" >&2
	exit 1
fi

# Docker only takes a boolean --pull, so podman's --pull=missing is passed there
# only, and image lookups use the subcommand each engine provides.
if [ "$CONTAINER_ENGINE" = "docker" ]; then
	PULL_FLAG=--pull
else
	PULL_FLAG=--pull=missing
fi

image_exists() {
	if [ "$CONTAINER_ENGINE" = "podman" ]; then
		"$CONTAINER_ENGINE" image exists "$1" >/dev/null 2>&1
	else
		"$CONTAINER_ENGINE" image inspect "$1" >/dev/null 2>&1
	fi
}

# The Amp CLI and Desktop runtime are copied out of Amp's published image.
if ! image_exists "$AMP_IMAGE"; then
	echo "Pulling $AMP_IMAGE ..."
	"$CONTAINER_ENGINE" pull "$AMP_IMAGE"
fi
if ! image_exists "$BASE_IMAGE"; then
	echo "Pulling $BASE_IMAGE ..."
	"$CONTAINER_ENGINE" pull "$BASE_IMAGE"
fi

echo "Building $IMAGE from $BASE_IMAGE ..."
"$CONTAINER_ENGINE" build \
	"$PULL_FLAG" \
	--build-arg "AMP_IMAGE=$AMP_IMAGE" \
	--build-arg "ARCH_MIRROR=$ARCH_MIRROR" \
	--build-arg "ARCHLINUXCN_MIRROR=$ARCHLINUXCN_MIRROR" \
	-t "$IMAGE" \
	-f Dockerfile \
	.

echo
echo "Built $IMAGE"
"$CONTAINER_ENGINE" image inspect "$IMAGE" --format '{{.Id}} {{.Size}}'
