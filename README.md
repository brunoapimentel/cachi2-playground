# Hermeto playground

A simple shell script to perform a hermetic build using [Hermeto](https://github.com/hermetoproject/hermeto) to prefetch the dependencies.

The script takes a git repo as the input param, and will clone, prefetch, inject project files,
and build it using buildah while cutting all network access.

## How to use

1. Edit the params in the `input.env` file
2. Run ./clone-and-build.sh

