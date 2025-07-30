#!/bin/bash

source ${1:-input.env}

SCRIPT_DIR=$(pwd)
TMP_DIR=$(mktemp -d "/tmp/hermeto.play.XXXXXXXXXX")

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
	-v $(realpath ./sources):/tmp/sources:z \
	-v $(realpath ./output):/tmp/output:z \
	"$HERMETO_IMAGE" \
	--log-level "DEBUG" \
	fetch-deps "$PREFETCH_INPUT" \
	--source "/tmp/sources" \
	--output "/tmp/output" \
	--dev-package-managers

# generate environmnent variables
podman run --rm \
	-v $(realpath ./sources):/tmp/sources:z \
	-v $(realpath ./output):/tmp/output:z \
	"$HERMETO_IMAGE" \
	generate-env /tmp/output \
	--format env \
	--output /tmp/output/prefetch.env

mv ./output/prefetch.env .

# inject project files
podman run --rm \
	-v $(realpath ./sources):/tmp/sources:z \
	-v $(realpath ./output):/tmp/output:z \
	"$HERMETO_IMAGE" \
	inject-files /tmp/output

# use the hermeto env variables in all RUN instructions in the Containerfile
sed -i 's|^\s*run |RUN . /tmp/prefetch.env \&\& \\\n    |i' "./sources/$CONTAINERFILE_PATH"

# in case RPMs for x86_64 were prefetched, mount the repofiles during the container build
if [ -d "./output/deps/rpm/x86_64/repos.d" ]; then
	echo "rpms found"
	MOUNT_RPM_REPOS="-v $(realpath ./output/deps/rpm/x86_64/repos.d):/etc/yum.repos.d"
fi

# build hermetically
podman build -t "$OUTPUT_IMAGE" \
	-v $(realpath ./output):/tmp/output:Z \
	-v $(realpath ./prefetch.env):/tmp/prefetch.env \
	$MOUNT_RPM_REPOS \
	--no-cache \
	--network=none \
	-f "./sources/$CONTAINERFILE_PATH" \
	sources
