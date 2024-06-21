#!/bin/bash
source input.env

SCRIPT_DIR=$(pwd)
TMP_DIR=$(mktemp -d)

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
	"$CACHI2_IMAGE" \
	--log-level "DEBUG" \
	fetch-deps "$PREFETCH_INPUT" \
	--source "/tmp/sources" \
	--output "/tmp/output" \
	--dev-package-managers

# generate environmnent variables
podman run --rm \
	-v $(realpath ./sources):/tmp/sources:z \
        -v $(realpath ./output):/tmp/output:z \
	"$CACHI2_IMAGE" \
	generate-env /tmp/output \
	--format env \
	--output /tmp/output/cachi2.env

mv ./output/cachi2.env .

# inject project files
podman run --rm \
        -v $(realpath ./sources):/tmp/sources:z \
        -v $(realpath ./output):/tmp/output:z \
        "$CACHI2_IMAGE" \
        inject-files /tmp/output

# use the cachi2 env variables in all RUN instructions in the Containerfile
sed -i 's|^\s*run |RUN . /tmp/cachi2.env \&\& \\\n    |i' "./sources/$CONTAINERFILE_PATH"

# build hermetically
podman build -t "$OUTPUT_IMAGE" \
        -v $(realpath ./output):/tmp/output:Z \
	-v $(realpath ./cachi2.env):/tmp/cachi2.env \
	--no-cache \
	--network=none \
	-f "./sources/$CONTAINERFILE_PATH" \
	sources

