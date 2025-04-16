#!/bin/bash

source ${1:-input.env}

SCRIPT_DIR=$(pwd)
TMP_DIR=$(mktemp -d "/tmp/cachi2.play.XXXXXXXXXX")
OUTPUT_MOUNT_DIR=/tmp/output
SOURCE_MOUNT_DIR=/tmp/sources

set -ex

# clone source code
cd $TMP_DIR
git clone "$GIT_REPO" sources

cd sources
git checkout "$REF"
cd ..

mkdir output

# prefetch dependencies
podman run --rm \
	-v $(realpath ./sources):"$SOURCE_MOUNT_DIR":z \
	-v $(realpath ./output):"$OUTPUT_MOUNT_DIR":z \
	"$CACHI2_IMAGE" \
	--log-level "DEBUG" \
	fetch-deps "$PREFETCH_INPUT" \
	--source "$SOURCE_MOUNT_DIR" \
	--output "$OUTPUT_MOUNT_DIR" \
	--dev-package-managers

# generate environmnent variables
podman run --rm \
	-v $(realpath ./sources):"$SOURCE_MOUNT_DIR":z \
	-v $(realpath ./output):"$OUTPUT_MOUNT_DIR":z \
	"$CACHI2_IMAGE" \
	generate-env "$OUTPUT_MOUNT_DIR" \
	--format env \
	--output "$OUTPUT_MOUNT_DIR/cachi2.env"

# inject project files
podman run --rm \
	-v $(realpath ./sources):"$SOURCE_MOUNT_DIR":z \
	-v $(realpath ./output):"$OUTPUT_MOUNT_DIR":z \
	"$CACHI2_IMAGE" \
	inject-files "$OUTPUT_MOUNT_DIR"

# use the cachi2 env variables in all RUN instructions in the Containerfile
sed -i "s|^\s*run |RUN . $OUTPUT_MOUNT_DIR/cachi2.env \&\& |i" "./sources/$CONTAINERFILE_PATH"

# in case RPMs for x86_64 were prefetched, mount the repofiles during the container build
if [ -d "./output/deps/rpm/x86_64/repos.d" ]; then
	echo "rpms found"
	MOUNT_RPM_REPOS="-v $(realpath ./output/deps/rpm/x86_64/repos.d):/etc/yum.repos.d"
fi

# build hermetically
podman build -t "$OUTPUT_IMAGE" \
	-v $(realpath ./output):"$OUTPUT_MOUNT_DIR":z \
	$MOUNT_RPM_REPOS \
	--network=none \
	-f "./sources/$CONTAINERFILE_PATH" \
	sources
