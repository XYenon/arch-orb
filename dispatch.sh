#!/usr/bin/env bash
# Docker dispatch program for Amp self-hosted orbs using the arch-orb image.
#
# Run the provider with ORB_IMAGE=arch-orb:latest so Amp passes this image to
# every spawn job:
#
#   export ORB_IMAGE=arch-orb:latest
#   amp orb provider ./dispatch.sh
#
# Each operation is safe to repeat and finishes well within Amp's five-minute
# limit. Pause keeps the disk; when Amp supplies ORB_SNAPSHOT_ID, the container
# is committed to a local image for project snapshots.

set -euo pipefail

: "${ORB_OPERATION:?ORB_OPERATION is required}"
: "${ORB_ID:?ORB_ID is required}"

CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}
IMAGE=${ORB_IMAGE:-arch-orb:latest}
PLATFORM=${ORB_PLATFORM:-linux/amd64}
SNAPSHOT=${ORB_SNAPSHOT_ID:-}

container_exists() {
	if [ "$CONTAINER_ENGINE" = "podman" ]; then
		"$CONTAINER_ENGINE" container exists "$ORB_ID" >/dev/null 2>&1
	else
		"$CONTAINER_ENGINE" inspect "$ORB_ID" >/dev/null 2>&1
	fi
}

image_exists() {
	if [ "$CONTAINER_ENGINE" = "podman" ]; then
		"$CONTAINER_ENGINE" image exists "$1" >/dev/null 2>&1
	else
		"$CONTAINER_ENGINE" image inspect "$1" >/dev/null 2>&1
	fi
}

case "$ORB_OPERATION" in
spawn)
	if [ -n "$SNAPSHOT" ] && image_exists "$SNAPSHOT"; then
		boot_image=$SNAPSHOT
	else
		boot_image=$IMAGE
	fi

	if container_exists; then
		"$CONTAINER_ENGINE" start "$ORB_ID" >/dev/null
	else
		# --shm-size is needed by Chrome in the Desktop tab; --init reaps child
		# processes that Amp starts and stops over the life of the orb.
		"$CONTAINER_ENGINE" run \
			--init \
			--platform "$PLATFORM" \
			--shm-size=1g \
			--name "$ORB_ID" \
			-d \
			"$boot_image" \
			sleep infinity
	fi

	env_args=(--env ORB_TOKEN)
	if [ -n "${AMP_URL:-}" ]; then
		env_args+=(--env AMP_URL)
	fi

	# The image's default user is "user"; bootstrap runs detached as that user.
	# $HOME belongs to the container, so the single quotes are intentional.
	# shellcheck disable=SC2016
	"$CONTAINER_ENGINE" exec -d "${env_args[@]}" "$ORB_ID" \
		bash -c 'exec amp orb bootstrap >>"$HOME/.amp-bootstrap.log" 2>&1'
	;;

pause)
	if container_exists; then
		"$CONTAINER_ENGINE" stop "$ORB_ID" >/dev/null 2>&1 || true
		if [ -n "$SNAPSHOT" ]; then
			"$CONTAINER_ENGINE" commit "$ORB_ID" "$SNAPSHOT" >/dev/null
		fi
	fi
	;;

delete)
	if container_exists; then
		"$CONTAINER_ENGINE" rm -f "$ORB_ID" >/dev/null
	fi
	;;

*)
	echo "unknown ORB_OPERATION: $ORB_OPERATION" >&2
	exit 1
	;;
esac
